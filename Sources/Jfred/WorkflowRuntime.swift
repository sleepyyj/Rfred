import Foundation
import JfredCore

enum WorkflowRuntime {
    static let runner = ProcessWorkflowRunner()

    static func engine(for workflow: Workflow) -> WorkflowEngine {
        WorkflowEngine(
            workflow: workflow,
            runner: runner,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func match(in workflows: [Workflow], query: String, disabledBuiltins: Set<String>) -> WorkflowMatch? {
        WorkflowEngine.match(in: workflows, query: query, disabledBuiltins: disabledBuiltins)
    }

    static func rows(for match: WorkflowMatch, result: WorkflowScriptFilterResult) -> [SearchResult] {
        let invocation = match.invocation
        return result.items.enumerated().compactMap { index, item in
            guard let payload = WorkflowRunPayload(invocation: invocation, item: item).json else { return nil }
            let suffix = item.uid.isEmpty ? String(index) : item.uid
            return SearchResult(
                id: "wf:\(match.workflow.id.uuidString):\(match.input.id.uuidString):\(suffix)",
                title: item.title.isEmpty ? match.workflow.name : item.title,
                subtitle: item.subtitle.isEmpty ? match.workflow.details : item.subtitle,
                icon: icon(for: item, workflow: match.workflow, objectUID: match.input.alfredUID),
                kind: "workflow",
                payload: payload,
                category: "action",
                score: 2
            )
        }
    }

    static func directRow(for match: WorkflowMatch) -> SearchResult? {
        guard let payload = WorkflowRunPayload(invocation: match.invocation).json else { return nil }
        return SearchResult(
            id: "wf:\(match.workflow.id.uuidString):\(match.input.id.uuidString)",
            title: match.workflow.name,
            subtitle: match.workflow.details.isEmpty ? "Workflow  ·  \(match.invocation.keyword)" : match.workflow.details,
            icon: WorkflowIcon.resolve(
                path: "",
                workflowRoot: match.workflow.rootPath,
                workflowSymbol: match.workflow.symbol,
                objectUID: match.input.alfredUID
            ).resource,
            kind: "workflow",
            payload: payload,
            category: "action",
            score: 2
        )
    }

    static func run(payload: WorkflowRunPayload, workflows: [Workflow], forced: String) async -> WorkflowRunState? {
        guard let workflow = workflows.first(where: { $0.id == payload.workflowID }) else { return nil }
        let invocation = WorkflowInvocation(
            workflowID: payload.workflowID,
            inputID: payload.inputID,
            keyword: payload.keyword,
            argument: payload.argument,
            variables: payload.variables
        )
        let modifier = WorkflowModifier(forced: forced)
        if let item = payload.item {
            let applied = item.applying(modifier: modifier)
            guard applied.valid else {
                return WorkflowRunState(pending: [], logs: [
                    WorkflowLogEntry(objectID: payload.inputID, title: "Workflow", detail: "This result is not valid for the current query.", isError: true)
                ])
            }
        }
        return await engine(for: workflow).run(invocation: invocation, item: payload.item, modifier: modifier)
    }

    static func icon(for item: WorkflowItem, workflow: Workflow, objectUID: String? = nil) -> String {
        WorkflowIcon.resolve(
            path: item.iconPath,
            type: item.iconType,
            workflowRoot: workflow.rootPath,
            workflowSymbol: workflow.symbol,
            objectUID: objectUID
        ).resource
    }
}
