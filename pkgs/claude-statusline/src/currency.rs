//! Locale-aware currency conversion for the cost segment.
//!
//! Strategy: cache a `(symbol, code, usd_rate)` triple in `/tmp` and
//! reuse it across renders. `/tmp` is the right home - it survives for
//! the duration of the user's login session but the OS clears it on
//! reboot, which gives us a free "refresh once per boot" cadence
//! without having to track timestamps ourselves.
//!
//! On a cache miss we fire two best-effort HTTP calls back-to-back:
//!
//! 1. <https://ipapi.co/json/> - geo-IP -> ISO country code (no key, no
//!    rate-limit auth). The country code maps deterministically to a currency via
//!    [`country_to_currency`].
//! 2. <https://open.er-api.com/v6/latest/USD> - exchange rates from USD to
//!    everything (no key, daily refresh upstream).
//!
//! Either failing -> fall back to USD silently. We never block the
//! prompt for more than [`FETCH_TIMEOUT`] total. The whole module is a
//! "best-effort polish" feature; the cost segment must keep working
//! even if the network is down or `/tmp` is read-only.

// `resolve()` short-circuits to USD under `cfg(test)` so tests never
// touch the network or the on-disk cache. The branch is a runtime
// `cfg!(test)` rather than two `#[cfg]` copies so that rust-analyzer
// always sees the full function body (avoiding false "inactive code"
// and "dead code" diagnostics).

use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::Duration;

use serde::{Deserialize, Serialize};

/// Resolved per-session currency.
///
/// `usd_rate` is the multiplier to apply to a USD amount; for USD
/// itself it's `1.0`. Held in a `OnceLock` so the geoip + FX fetch
/// happens at most once per process even if the cost segment renders
/// many times in a single invocation (e.g. tests, benches, the preview
/// pipeline).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Currency {
    pub symbol: String,
    pub code: String,
    pub usd_rate: f64,
}

impl Currency {
    pub fn usd() -> Self {
        Self {
            symbol: "$".into(),
            code: "USD".into(),
            usd_rate: 1.0,
        }
    }
}

/// Tight overall budget for the geoip + FX round trip. Two requests
/// share this; if either is slow we fall back to USD. The prompt
/// budget for a single render is well under a second, so we'd rather
/// show dollars than block.
const FETCH_TIMEOUT: Duration = Duration::from_millis(800);

static RESOLVED: OnceLock<Currency> = OnceLock::new();

/// Return the (cached, lazily-resolved) currency for this process.
/// First call: read the `/tmp` cache, or fetch+cache, or fall back
/// to USD. Subsequent calls: cheap `OnceLock` read.
pub fn current() -> &'static Currency {
    RESOLVED.get_or_init(resolve)
}

/// Resolve the currency by walking the cache -> geoip -> FX pipeline.
/// Each step is a hard "fall back to USD" boundary; the function never
/// returns an error.
///
/// `CLAUDE_STATUSLINE_CURRENCY` short-circuits the entire pipeline:
/// set it to `USD` to force the historical dollar formatting, or to a
/// supported ISO code (`EUR`, `JPY`, …) to pin a specific currency
/// without relying on geo-IP.
///
/// Under `cfg(test)` the function short-circuits to USD so tests never
/// touch the network or the on-disk cache.
fn resolve() -> Currency {
    if cfg!(test) {
        return Currency::usd();
    }
    if let Ok(forced) = std::env::var("CLAUDE_STATUSLINE_CURRENCY")
        && let Some(c) = currency_from_code(forced.trim())
    {
        return c;
    }
    if let Some(c) = read_cache() {
        return c;
    }
    if let Some(c) = fetch_and_cache() {
        return c;
    }
    Currency::usd()
}

/// Look up a currency by ISO code without going through geo-IP. Used by
/// the `CLAUDE_STATUSLINE_CURRENCY` override. Sets `usd_rate` to `1.0`
/// for non-USD codes because we don't have FX data without a network
/// call.
fn currency_from_code(code: &str) -> Option<Currency> {
    if code.eq_ignore_ascii_case("USD") {
        return Some(Currency::usd());
    }
    let iso = iso_currency::Currency::from_code(code)?;
    Some(Currency {
        symbol: display_symbol(iso),
        code: iso.code().to_owned(),
        usd_rate: 1.0,
    })
}

/// Return a compact display symbol for a currency. For currencies that
/// share a `$` glyph, we prefix with the country code to disambiguate
/// (e.g. `C$` for CAD, `A$` for AUD). For everything else we use the
/// ISO 4217 symbol directly.
fn display_symbol(c: iso_currency::Currency) -> String {
    match c {
        iso_currency::Currency::CAD => "C$",
        iso_currency::Currency::AUD => "A$",
        iso_currency::Currency::NZD => "NZ$",
        iso_currency::Currency::MXN => "MX$",
        iso_currency::Currency::ARS => "AR$",
        iso_currency::Currency::CLP => "CLP$",
        iso_currency::Currency::COP => "COL$",
        iso_currency::Currency::SGD => "S$",
        iso_currency::Currency::TWD => "NT$",
        iso_currency::Currency::BRL => "R$",
        iso_currency::Currency::CHF => "CHF ",
        _ => return c.symbol().to_string(),
    }
    .into()
}

/// Cache file lives in `/tmp` (cleared on reboot, which is exactly the
/// "refresh once per boot" cadence we want). Falls back to the
/// platform temp dir if `/tmp` somehow isn't writable.
fn cache_path() -> PathBuf {
    let base = if cfg!(unix) {
        PathBuf::from("/tmp")
    } else {
        std::env::temp_dir()
    };
    base.join("claude-statusline-currency.json")
}

fn read_cache() -> Option<Currency> {
    let bytes = fs::read(cache_path()).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn write_cache(c: &Currency) {
    if let Ok(bytes) = serde_json::to_vec(c) {
        let _ = fs::write(cache_path(), bytes);
    }
}

fn fetch_and_cache() -> Option<Currency> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(FETCH_TIMEOUT))
        .user_agent(concat!("claude-statusline/", env!("CARGO_PKG_VERSION")))
        .build()
        .into();

    let country = fetch_country(&agent)?;
    let (code, symbol) = country_to_currency(&country)?;
    if code == "USD" {
        let c = Currency::usd();
        write_cache(&c);
        return Some(c);
    }
    let rate = fetch_rate(&agent, &code)?;
    if !rate.is_finite() || rate <= 0.0 {
        return None;
    }
    let c = Currency {
        symbol,
        code,
        usd_rate: rate,
    };
    write_cache(&c);
    Some(c)
}

#[derive(Deserialize)]
struct IpApi {
    country_code: Option<String>,
}

fn fetch_country(agent: &ureq::Agent) -> Option<String> {
    let mut resp = agent.get("https://ipapi.co/json/").call().ok()?;
    let body = resp
        .body_mut()
        .with_config()
        .limit(64 * 1024)
        .read_to_vec()
        .ok()?;
    let parsed: IpApi = serde_json::from_slice(&body).ok()?;
    parsed.country_code.filter(|c| !c.is_empty())
}

#[derive(Deserialize)]
struct ErApi {
    result: Option<String>,
    rates: Option<std::collections::HashMap<String, f64>>,
}

fn fetch_rate(agent: &ureq::Agent, code: &str) -> Option<f64> {
    let mut resp = agent
        .get("https://open.er-api.com/v6/latest/USD")
        .call()
        .ok()?;
    let body = resp
        .body_mut()
        .with_config()
        .limit(256 * 1024)
        .read_to_vec()
        .ok()?;
    let parsed: ErApi = serde_json::from_slice(&body).ok()?;
    if parsed.result.as_deref() != Some("success") {
        return None;
    }
    parsed.rates?.get(code).copied()
}

/// Map an ISO 3166-1 alpha-2 country code to its primary `(code, symbol)`
/// pair. Uses the `iso_currency` crate for the country→currency lookup
/// and our [`display_symbol`] helper for disambiguated symbols.
///
/// Returns `None` for unrecognised country codes, which the caller
/// treats as "fall back to USD".
pub fn country_to_currency(country: &str) -> Option<(String, String)> {
    let upper = country.to_ascii_uppercase();
    let country_enum: iso_currency::Country = upper.parse().ok()?;
    let iso = iso_currency::Currency::from(country_enum);
    let code = iso.code().to_owned();
    let symbol = display_symbol(iso);
    Some((code, symbol))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eurozone_resolves_to_euro() {
        assert_eq!(country_to_currency("DE"), Some(("EUR".into(), "€".into())));
        assert_eq!(country_to_currency("fr"), Some(("EUR".into(), "€".into())));
    }

    #[test]
    fn poland_is_zloty() {
        assert_eq!(country_to_currency("PL"), Some(("PLN".into(), "zł".into())));
    }

    #[test]
    fn unknown_country_returns_none() {
        assert!(country_to_currency("ZZ").is_none());
    }

    #[test]
    fn usd_currency_default() {
        let u = Currency::usd();
        assert_eq!(u.code, "USD");
        assert_eq!(u.usd_rate, 1.0);
    }
}
