{
  lib,
  lldb,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "codex-lldb-mcp";
  version = lldb.version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${./codex-lldb-mcp.py} "$out/bin/codex-lldb-mcp"
    substituteInPlace "$out/bin/codex-lldb-mcp" \
      --replace-fail '@python@' '${lib.getExe python3}' \
      --replace-fail '@lldb@' '${lib.getExe' lldb "lldb"}' \
      --replace-fail '@lldb_mcp@' '${lib.getExe' lldb "lldb-mcp"}'

    ${lib.getExe python3} -m py_compile "$out/bin/codex-lldb-mcp"

    runHook postInstall
  '';

  meta = {
    description = "Codex launcher for LLDB's built-in MCP stdio bridge";
    homepage = "https://lldb.llvm.org/use/mcp.html";
    license = lib.licenses.asl20;
    mainProgram = "codex-lldb-mcp";
    platforms = lib.platforms.unix;
  };
}
