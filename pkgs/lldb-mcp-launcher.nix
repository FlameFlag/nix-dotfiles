{
  lib,
  lldb,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "lldb-mcp-launcher";
  version = lldb.version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${./lldb-mcp-launcher.py} "$out/bin/lldb-mcp-launcher"
    substituteInPlace "$out/bin/lldb-mcp-launcher" \
      --replace-fail '@python@' '${lib.getExe python3}' \
      --replace-fail '@lldb@' '${lib.getExe' lldb "lldb"}' \
      --replace-fail '@lldb_mcp@' '${lib.getExe' lldb "lldb-mcp"}'

    ${lib.getExe python3} -m py_compile "$out/bin/lldb-mcp-launcher"

    runHook postInstall
  '';

  meta = {
    description = "Launcher for LLDB's built-in MCP stdio bridge";
    homepage = "https://lldb.llvm.org/use/mcp.html";
    license = lib.licenses.asl20;
    mainProgram = "lldb-mcp-launcher";
    platforms = lib.platforms.unix;
  };
}
