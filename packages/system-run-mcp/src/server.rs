use rmcp::{
    ErrorData, ServerHandler,
    handler::server::{
        router::tool::ToolRouter,
        wrapper::{Json, Parameters},
    },
    tool, tool_handler, tool_router,
};
use tokio_util::sync::CancellationToken;

use crate::command::{SystemRunParams, run_system_command};
use crate::output::SystemRunOutput;

#[derive(Debug, Clone)]
pub(crate) struct SystemRunServer {
    tool_router: ToolRouter<Self>,
}

impl SystemRunServer {
    pub(crate) fn new() -> Self {
        Self {
            tool_router: Self::tool_router(),
        }
    }
}

#[tool_router(router = tool_router)]
impl SystemRunServer {
    #[tool(
        name = "system-run",
        title = "System Run",
        description = "Run an arbitrary shell command through the local system command runner.",
        annotations(
            title = "System Run",
            read_only_hint = false,
            destructive_hint = true,
            idempotent_hint = false,
            open_world_hint = true
        ),
        execution(task_support = "forbidden")
    )]
    async fn system_run(
        &self,
        Parameters(params): Parameters<SystemRunParams>,
        cancellation_token: CancellationToken,
    ) -> Result<Json<SystemRunOutput>, ErrorData> {
        run_system_command(params, cancellation_token).await
    }
}

#[tool_handler(
    router = self.tool_router,
    name = "system-run-mcp",
    instructions = "system-run executes shell commands through sudo -n system-runner. Command exit failures are returned as structured output with success=false, exit_status, stdout, and stderr; only invalid input or runner setup failures are JSON-RPC errors."
)]
impl ServerHandler for SystemRunServer {}

#[cfg(test)]
mod tests {
    use rmcp::{ServerHandler, model::TaskSupport};

    use super::*;

    #[test]
    fn generated_tool_metadata_is_protocol_rich() -> Result<(), &'static str> {
        let tool = SystemRunServer::system_run_tool_attr();

        assert_eq!(tool.name, "system-run");
        assert_eq!(tool.title.as_deref(), Some("System Run"));
        assert!(tool.output_schema.is_some());

        let annotations = tool.annotations.ok_or("tool annotations")?;
        assert_eq!(annotations.title.as_deref(), Some("System Run"));
        assert_eq!(annotations.read_only_hint, Some(false));
        assert_eq!(annotations.destructive_hint, Some(true));
        assert_eq!(annotations.idempotent_hint, Some(false));
        assert_eq!(annotations.open_world_hint, Some(true));

        let execution = tool.execution.ok_or("tool execution")?;
        assert_eq!(execution.task_support, Some(TaskSupport::Forbidden));
        Ok(())
    }

    #[test]
    fn generated_server_info_includes_tool_capability_and_instructions() {
        let info = SystemRunServer::new().get_info();

        assert_eq!(info.server_info.name, "system-run-mcp");
        assert_eq!(info.server_info.version, env!("CARGO_PKG_VERSION"));
        assert!(info.capabilities.tools.is_some());
        assert!(
            info.instructions
                .as_deref()
                .is_some_and(|instructions| instructions.contains("success=false"))
        );
    }
}
