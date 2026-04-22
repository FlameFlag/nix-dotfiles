# Chezmoi TypeScript Library

Chezmoi executes scripts from temporary files, so runtime imports that are
relative to a script file do not resolve back into the source directory.
Scripts use a type-only local import for TypeScript checking and a runtime
`CHEZMOI_SOURCE_DIR` file URL import for this shared library.
