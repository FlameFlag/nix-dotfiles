(import
  (rnrs)
  (entries apps)
  (entries ecosystem)
  (entries local)
  (entries prerequisites)
  (scaffold catalog))

(moduledoc
  (summary
    "Root Scaffold catalog that combines prerequisite, ecosystem, application, and local tools.")
  (group "Dotfiles catalog"))

(apply
  catalog
  (append
    (append (append (prerequisites/tools) (ecosystem/tools)) (apps/tools))
    (local/tools)))
