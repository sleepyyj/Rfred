import RfredCore
import SwiftUI

extension AppModel {
    func bind<T: Sendable>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>) -> Binding<T> {
        Binding(
            get: { MainActor.assumeIsolated { self[keyPath: keyPath] } },
            set: { newValue in MainActor.assumeIsolated { self[keyPath: keyPath] = newValue } }
        )
    }

    func bindPref<T: Sendable>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { MainActor.assumeIsolated { self.preferences[keyPath: keyPath] } },
            set: { newValue in MainActor.assumeIsolated { self.preferences[keyPath: keyPath] = newValue } }
        )
    }

    func bindElement(_ keyPath: WritableKeyPath<Preferences, [String]>, _ index: Int) -> Binding<String> {
        Binding(
            get: { MainActor.assumeIsolated { self.preferences[keyPath: keyPath].indices.contains(index) ? self.preferences[keyPath: keyPath][index] : "" } },
            set: { newValue in
                MainActor.assumeIsolated {
                    var list = self.preferences[keyPath: keyPath]
                    guard list.indices.contains(index) else { return }
                    list[index] = newValue
                    self.preferences[keyPath: keyPath] = list
                }
            }
        )
    }

    func bindSystemKeyword(_ id: String, default fallback: String) -> Binding<String> {
        Binding(
            get: { MainActor.assumeIsolated { self.preferences.systemKeywords[id] ?? fallback } },
            set: { newValue in
                MainActor.assumeIsolated {
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        self.preferences.systemKeywords.removeValue(forKey: id)
                    } else {
                        self.preferences.systemKeywords[id] = trimmed
                    }
                }
            }
        )
    }

    func bindMember(_ keyPath: WritableKeyPath<Preferences, [String]>, _ value: String) -> Binding<Bool> {
        Binding(
            get: { MainActor.assumeIsolated { self.preferences[keyPath: keyPath].contains(value) } },
            set: { on in
                MainActor.assumeIsolated {
                    var list = self.preferences[keyPath: keyPath]
                    if on {
                        if !list.contains(value) { list.append(value) }
                    } else {
                        list.removeAll { $0 == value }
                    }
                    self.preferences[keyPath: keyPath] = list
                }
            }
        )
    }

    func bindWeb<T: Sendable>(_ index: Int, _ keyPath: WritableKeyPath<WebSearch, T>) -> Binding<T> {
        Binding(
            get: { MainActor.assumeIsolated { self.preferences.webSearches[index][keyPath: keyPath] } },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard self.preferences.webSearches.indices.contains(index) else { return }
                    self.preferences.webSearches[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    func bindSnippet<T: Sendable>(_ index: Int, _ keyPath: WritableKeyPath<Snippet, T>) -> Binding<T> {
        Binding(
            get: { MainActor.assumeIsolated { self.snippets[index][keyPath: keyPath] } },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard self.snippets.indices.contains(index) else { return }
                    self.snippets[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    func bindWorkflow<T: Sendable>(_ id: UUID, _ keyPath: WritableKeyPath<Workflow, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: { MainActor.assumeIsolated { self.workflows.first { $0.id == id }?[keyPath: keyPath] ?? defaultValue } },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard let index = self.workflows.firstIndex(where: { $0.id == id }) else { return }
                    self.workflows[index][keyPath: keyPath] = newValue
                    self.workflowEdited()
                    self.applyHotkeys()
                }
            }
        )
    }

    func bindAction<T: Sendable>(_ id: UUID, _ index: Int, _ keyPath: WritableKeyPath<WorkflowAction, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    guard let workflow = self.workflows.first(where: { $0.id == id }),
                          workflow.actions.indices.contains(index) else { return defaultValue }
                    return workflow.actions[index][keyPath: keyPath]
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard let workflowIndex = self.workflows.firstIndex(where: { $0.id == id }),
                          self.workflows[workflowIndex].actions.indices.contains(index) else { return }
                    self.workflows[workflowIndex].actions[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    func beginWorkflowEdit(_ workflow: Workflow) {
        if let existing = workflows.first(where: { $0.id == workflow.id }) {
            workflowSnapshot = existing
            workflowIsNew = false
        } else {
            workflows.append(workflow)
            workflowSnapshot = nil
            workflowIsNew = true
        }
        editingWorkflowID = workflow.id
        selectedWorkflow = workflow.id
        workflowSelection = nil
        selectedWorkflowObject = workflow.searchInputs.first?.id
        debuggerVisible = false
        debugLines = []
        debugCursor = 0
        debugWorkflowID = nil
        debugBreakpoints = []
        debugPaused = false
        workflowDebugState = nil
        debugLoggedCount = 0
        debugAppliedEffects = 0
        workflowConfigPresented = false
        workflowConfigShowsWorkflow = false
        workflowConfigEditsMetadata = false
        workflowConfigSnapshot = nil
    }

    func cancelWorkflowEdit() {
        guard let id = editingWorkflowID else { return }
        if workflowIsNew {
            workflows.removeAll { $0.id == id }
            selectedWorkflow = workflows.first?.id
        } else if let snapshot = workflowSnapshot, let index = workflows.firstIndex(where: { $0.id == id }) {
            workflows[index] = snapshot
        }
        editingWorkflowID = nil
        workflowSnapshot = nil
        workflowIsNew = false
        workflowSelection = nil
        selectedWorkflowObject = nil
        workflowDebugState = nil
        debugLoggedCount = 0
        debugAppliedEffects = 0
    }

    func saveWorkflowEdit() {
        editingWorkflowID = nil
        workflowSnapshot = nil
        workflowIsNew = false
        workflowSelection = nil
        workflowsChanged()
    }
}

extension AppModel {
    func bindWorkflowObject<T: Sendable>(_ workflowID: UUID, _ objectID: UUID, _ keyPath: WritableKeyPath<WorkflowObject, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    guard let workflow = self.workflows.first(where: { $0.id == workflowID }),
                          let object = workflow.object(id: objectID) else { return defaultValue }
                    return object[keyPath: keyPath]
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard let workflowIndex = self.workflows.firstIndex(where: { $0.id == workflowID }),
                          let objectIndex = self.workflows[workflowIndex].objects.firstIndex(where: { $0.id == objectID }) else { return }
                    self.workflows[workflowIndex].objects[objectIndex][keyPath: keyPath] = newValue
                    self.workflowEdited()
                }
            }
        )
    }

    func bindWorkflowString(_ workflowID: UUID, _ objectID: UUID, _ key: String, default defaultValue: String = "") -> Binding<String> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    self.workflows.first { $0.id == workflowID }?.object(id: objectID)?.config[string: key] ?? defaultValue
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard let workflowIndex = self.workflows.firstIndex(where: { $0.id == workflowID }),
                          let objectIndex = self.workflows[workflowIndex].objects.firstIndex(where: { $0.id == objectID }) else { return }
                    self.workflows[workflowIndex].objects[objectIndex].config[key] = .string(newValue)
                    self.workflowEdited()
                }
            }
        )
    }

    func bindWorkflowInt(_ workflowID: UUID, _ objectID: UUID, _ key: String, default defaultValue: Int = 0) -> Binding<Int> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    self.workflows.first { $0.id == workflowID }?.object(id: objectID)?.config[key]?.intValue ?? defaultValue
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard let workflowIndex = self.workflows.firstIndex(where: { $0.id == workflowID }),
                          let objectIndex = self.workflows[workflowIndex].objects.firstIndex(where: { $0.id == objectID }) else { return }
                    self.workflows[workflowIndex].objects[objectIndex].config[key] = .integer(newValue)
                    self.workflowEdited()
                }
            }
        )
    }

    func bindWorkflowBool(_ workflowID: UUID, _ objectID: UUID, _ key: String, default defaultValue: Bool = false) -> Binding<Bool> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    self.workflows.first { $0.id == workflowID }?.object(id: objectID)?.config[key]?.boolValue ?? defaultValue
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard let workflowIndex = self.workflows.firstIndex(where: { $0.id == workflowID }),
                          let objectIndex = self.workflows[workflowIndex].objects.firstIndex(where: { $0.id == objectID }) else { return }
                    self.workflows[workflowIndex].objects[objectIndex].config[key] = .boolean(newValue)
                    self.workflowEdited()
                }
            }
        )
    }

    func bindWorkflowVariables(_ workflowID: UUID, _ objectID: UUID) -> Binding<String> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    guard let object = self.workflows.first(where: { $0.id == workflowID })?.object(id: objectID) else { return "" }
                    return object.config.strings("variables").sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                }
            },
            set: { text in
                MainActor.assumeIsolated {
                    guard let workflowIndex = self.workflows.firstIndex(where: { $0.id == workflowID }),
                          let objectIndex = self.workflows[workflowIndex].objects.firstIndex(where: { $0.id == objectID }) else { return }
                    var variables: [String: WorkflowValue] = [:]
                    for line in text.split(separator: "\n") {
                        guard let equals = line.firstIndex(of: "=") else { continue }
                        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                        guard !key.isEmpty else { continue }
                        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                        variables[key] = .string(value)
                    }
                    self.workflows[workflowIndex].objects[objectIndex].config["variables"] = .object(variables)
                    self.workflowEdited()
                }
            }
        )
    }

    func bindWorkflowConditionString(_ workflowID: UUID, _ objectID: UUID, _ index: Int, _ key: String) -> Binding<String> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    guard let object = self.workflows.first(where: { $0.id == workflowID })?.object(id: objectID),
                          let conditions = object.config["conditions"]?.arrayValue,
                          conditions.indices.contains(index),
                          let bits = conditions[index].objectValue else { return "" }
                    return bits[string: key]
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    guard let workflowIndex = self.workflows.firstIndex(where: { $0.id == workflowID }),
                          let objectIndex = self.workflows[workflowIndex].objects.firstIndex(where: { $0.id == objectID }),
                          var conditions = self.workflows[workflowIndex].objects[objectIndex].config["conditions"]?.arrayValue,
                          conditions.indices.contains(index),
                          var bits = conditions[index].objectValue else { return }
                    bits[key] = .string(newValue)
                    conditions[index] = .object(bits)
                    self.workflows[workflowIndex].objects[objectIndex].config["conditions"] = .array(conditions)
                    self.workflowEdited()
                }
            }
        )
    }
}

extension AppModel {
    func bindWorkflowVariables(_ workflowID: UUID) -> Binding<String> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    guard let workflow = self.workflows.first(where: { $0.id == workflowID }) else { return "" }
                    return workflow.variables.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                }
            },
            set: { text in
                MainActor.assumeIsolated {
                    guard let index = self.workflows.firstIndex(where: { $0.id == workflowID }) else { return }
                    var variables: [String: String] = [:]
                    for line in text.split(separator: "\n") {
                        guard let equals = line.firstIndex(of: "=") else { continue }
                        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                        guard !key.isEmpty else { continue }
                        variables[key] = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                    }
                    self.workflows[index].variables = variables
                    self.workflowEdited()
                }
            }
        )
    }
}
