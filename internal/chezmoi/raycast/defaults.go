package raycast

import (
	_ "embed"
	"fmt"

	"github.com/pelletier/go-toml/v2"
)

//go:embed defaults.toml
var defaultData []byte

var defaultProfile = mustLoadDefaults(defaultData)

type currentUser struct {
	ID                   string       `json:"id"                       toml:"id"`
	Name                 string       `json:"name"                     toml:"name"`
	Username             string       `json:"username"                 toml:"username"`
	Handle               string       `json:"handle"                   toml:"handle"`
	Email                string       `json:"email"                    toml:"email"`
	Image                string       `json:"image"                    toml:"image"`
	Avatar               string       `json:"avatar"                   toml:"avatar"`
	Organizations        []string     `json:"organizations"            toml:"organizations"`
	HasProFeatures       bool         `json:"has_pro_features"         toml:"has_pro_features"`
	CanApplyForFreeTrial bool         `json:"can_apply_for_free_trial" toml:"can_apply_for_free_trial"`
	Subscription         subscription `json:"subscription"             toml:"subscription"`
}

type subscription struct {
	ID           string `json:"id"            toml:"id"`
	Status       string `json:"status"        toml:"status"`
	PlanName     string `json:"plan_name"     toml:"plan_name"`
	BillingCycle string `json:"billing_cycle" toml:"billing_cycle"`
	RenewalDate  string `json:"renewal_date"  toml:"renewal_date"`
}

type oauthToken struct {
	AccessToken  string `json:"access_token"  toml:"access_token"`
	RefreshToken string `json:"refresh_token" toml:"refresh_token"`
	TokenType    string `json:"token_type"    toml:"token_type"`
	ExpiresIn    int    `json:"expires_in"    toml:"expires_in"`
	Scope        string `json:"scope"         toml:"scope"`
}

type defaults struct {
	AvatarURL   string      `toml:"avatar_url"`
	CurrentUser currentUser `toml:"current_user"`
	OAuthToken  oauthToken  `toml:"oauth_token"`
}

func mustLoadDefaults(data []byte) defaults {
	defaults, err := loadDefaults(data)
	if err != nil {
		panic(err)
	}
	return defaults
}

func loadDefaults(data []byte) (defaults, error) {
	var defaults defaults
	if err := toml.Unmarshal(data, &defaults); err != nil {
		return defaults, fmt.Errorf("parse embedded Raycast defaults: %w", err)
	}
	if defaults.AvatarURL == "" {
		return defaults, fmt.Errorf("embedded Raycast defaults are missing avatar_url")
	}
	if defaults.CurrentUser.ID == "" || defaults.CurrentUser.Name == "" {
		return defaults, fmt.Errorf("embedded Raycast defaults are missing current_user identity")
	}
	if defaults.OAuthToken.AccessToken == "" {
		return defaults, fmt.Errorf("embedded Raycast defaults are missing oauth_token")
	}
	return defaults, nil
}
