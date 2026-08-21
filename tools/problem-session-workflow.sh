#!/usr/bin/env bash

# Artifact-system guidance for tools/problem-session.
# This file is sourced after the core functions so it can extend the command
# surface without weakening the existing workflow state machine.

resolve_session_or_active() {
    local requested="${1:-}"
    if [[ -n "$requested" ]]; then
        resolve_session_file "$requested"
        return 0
    fi

    collect_active_sessions
    ((${#ACTIVE_SESSIONS[@]} == 1)) ||
        die "expected exactly one active Session; pass a Session file explicitly"
    printf '%s\n' "${ACTIVE_SESSIONS[0]}"
}

session_card_rows() {
    local file="$1"
    awk '
        function flush_card() {
            if (id == "") return
            gsub(/\t/, " ", title)
            gsub(/\t/, " ", blocking)
            gsub(/\t/, " ", confirmation)
            print id "\t" kind "\t" checked "\t" has_confirmation "\t" placeholder "\t" blocking "\t" title "\t" confirmation
        }
        /^### [HDU]-[0-9]+([[:space:]]|$)/ {
            flush_card()
            id = $2
            kind = substr(id, 1, 1)
            title = $0
            sub(/^### [^[:space:]]+[[:space:]]*/, "", title)
            checked = 0
            has_confirmation = 0
            placeholder = 0
            blocking = ""
            confirmation = ""
            in_card = 1
            next
        }
        in_card && /^### / {
            flush_card()
            id = ""
            in_card = 0
        }
        in_card && /^## / {
            flush_card()
            id = ""
            in_card = 0
        }
        in_card {
            if ($0 ~ /^- \[[xX]\]/) checked = 1
            if ($0 ~ /^- 人工确认记录：/ || $0 ~ /^- Human Confirmation:/) {
                has_confirmation = 1
                confirmation = $0
            }
            if (index($0, "待填写") > 0) placeholder = 1
            if ($0 ~ /^- 是否阻塞当前节点：/) {
                blocking = $0
                sub(/^- 是否阻塞当前节点：[[:space:]]*/, "", blocking)
            }
        }
        END { flush_card() }
    ' "$file"
}

session_card_confirmed() {
    local file="$1" required_id="$2"
    session_card_rows "$file" | awk -F '\t' -v required="$required_id" '
        $1 == required {
            found = 1
            if ($3 == "1" && $4 == "1" && $5 == "0") valid = 1
        }
        END { exit !(found && valid) }
    '
}

validate_required_decisions() {
    local node="$1" decision_record="$2" required
    [[ -n "$decision_record" ]] || return 0

    while IFS= read -r required; do
        [[ -n "$required" ]] || continue
        session_card_confirmed "$decision_record" "$required" ||
            die "required human decision is missing, unchecked, or incomplete: $required"
    done < <(jq -r --arg node "$node" '
        first(.nodes[] | select(.id == $node) | .human_gate.required_decisions // [])[]?
    ' "$WORKFLOW_FILE")
}

section_has_content() {
    local file="$1" section="$2"
    awk -v heading="## $section" '
        $0 == heading { found = 1; inside = 1; next }
        inside && /^## / { inside = 0 }
        inside && $0 ~ /[^[:space:]]/ { content = 1 }
        END { exit !(found && content) }
    ' "$file"
}

show_workflow_status() {
    local json="${1:-false}" active_session='' active_session_rel=''
    require_workflow
    collect_active_sessions
    if ((${#ACTIVE_SESSIONS[@]} == 1)); then
        active_session="${ACTIVE_SESSIONS[0]}"
        active_session_rel="${active_session#$REPO_ROOT/}"
    fi

    if [[ "$json" == true ]]; then
        jq --arg active_session "$active_session_rel" '
            .nodes as $nodes
            | {
                workflowId: .workflow_id,
                problemId: .problem_id,
                state: .state,
                pattern: .pattern,
                activeSession: (if $active_session == "" then null else $active_session end),
                nodes: [
                    $nodes[] as $node
                    | {
                        id: $node.id,
                        title: $node.title,
                        phase: $node.phase,
                        status: $node.status,
                        attempts: (($node.attempts // []) | length),
                        dependsOn: ($node.depends_on // []),
                        missingDependencies: [
                            ($node.depends_on // [])[] as $dependency
                            | select(any($nodes[]; .id == $dependency and .status != "accepted"))
                            | $dependency
                        ],
                        requiredDecisions: ($node.human_gate.required_decisions // []),
                        humanGate: $node.human_gate,
                        unlocks: [$nodes[] | select((.depends_on // []) | index($node.id)) | .id],
                        nextAction: (
                            if $node.status == "ready" then "start"
                            elif $node.status == "active" then "instructions-review-verify"
                            elif $node.status == "awaiting-human" then "review-human-decisions"
                            elif $node.status == "verifying" then "verify-and-transition"
                            elif $node.status == "blocked" then "resolve-blocker"
                            else null end
                        )
                    }
                ]
            }
        ' "$WORKFLOW_FILE"
        return 0
    fi

    jq -r '
        "Workflow: \(.workflow_id)  state=\(.state)",
        "Pattern: \(.pattern.id)@\(.pattern.version)",
        "",
        "STATUS\tPHASE\tNODE\tATTEMPTS\tTITLE",
        (.nodes[] | "\(.status)\t\(.phase)\t\(.id)\t\((.attempts // []) | length)\t\(.title)")
    ' "$WORKFLOW_FILE"

    printf '\nActive Session:\n'
    if [[ -z "$active_session" ]]; then
        printf '  none\n'
    else
        printf '  %s  node=%s\n' "$active_session_rel" "$(session_workflow_node "$active_session")"
    fi

    printf '\nActionable Nodes:\n'
    jq -r '
        .nodes as $nodes
        | $nodes[] as $node
        | select($node.status == "ready" or $node.status == "active" or
                 $node.status == "awaiting-human" or $node.status == "verifying" or
                 $node.status == "blocked")
        | ([($node.depends_on // [])[] as $dependency
             | select(any($nodes[]; .id == $dependency and .status != "accepted"))
             | $dependency] | join(", ")) as $missing
        | (($node.human_gate.required_decisions // []) | join(", ")) as $decisions
        | "  \($node.id): status=\($node.status)"
          + (if $missing == "" then "" else " missing-deps=[\($missing)]" end)
          + (if $decisions == "" then "" else " required-decisions=[\($decisions)]" end)
    ' "$WORKFLOW_FILE"

    if [[ -n "$active_session" ]]; then
        printf '\nRecommended:\n'
        printf '  %s instructions %s\n' "$PROGRAM_NAME" "$(session_workflow_node "$active_session")"
        printf '  %s review %s\n' "$PROGRAM_NAME" "$active_session_rel"
    fi
}

show_node_instructions() {
    local node="$1" json="${2:-false}" active_session='' active_session_rel=''
    require_workflow
    workflow_node_exists "$node" || die "workflow node not found: $node"
    collect_active_sessions
    if ((${#ACTIVE_SESSIONS[@]} == 1)) && [[ "$(session_workflow_node "${ACTIVE_SESSIONS[0]}")" == "$node" ]]; then
        active_session_rel="${ACTIVE_SESSIONS[0]#$REPO_ROOT/}"
    fi

    if [[ "$json" == true ]]; then
        jq --arg node "$node" --arg active_session "$active_session_rel" '
            .nodes as $nodes
            | first($nodes[] | select(.id == $node)) as $target
            | {
                workflowId: .workflow_id,
                problemId: .problem_id,
                node: {
                    id: $target.id,
                    title: $target.title,
                    phase: $target.phase,
                    status: $target.status,
                    inputs: ($target.inputs // []),
                    outputs: ($target.outputs // []),
                    constraints: ($target.constraints // []),
                    requiredCapabilities: ($target.required_capabilities // []),
                    oracle: ($target.oracle // []),
                    humanGate: $target.human_gate,
                    attempts: ($target.attempts // []),
                    retentionTargets: ($target.retention_targets // [])
                },
                dependencies: [
                    ($target.depends_on // [])[] as $dependency
                    | first($nodes[] | select(.id == $dependency))
                    | {id, title, status}
                ],
                unlocks: [$nodes[] | select((.depends_on // []) | index($target.id)) | {id, title, status}],
                activeSession: (if $active_session == "" then null else $active_session end),
                rules: {
                    stateAuthority: ".problems/<problem-id>/WORKFLOW.json",
                    rereadFromDisk: true,
                    fileExistenceIsNotCompletion: true,
                    agentCannotAcceptHumanGate: true
                }
            }
        ' "$WORKFLOW_FILE"
        return 0
    fi

    show_node_instructions "$node" true | jq -r '
        "节点：\(.node.id)（\(.node.title)）",
        "阶段/状态：\(.node.phase) / \(.node.status)",
        "当前会话：\(.activeSession // "none")",
        "依赖：" + ([.dependencies[] | "\(.id)=\(.status)"] | if length == 0 then "无" else join("；") end),
        "输入：" + (.node.inputs | if length == 0 then "未显式声明" else join("；") end),
        "预期产物：" + (.node.outputs | if length == 0 then "未显式声明" else join("；") end),
        "所需能力：" + (.node.requiredCapabilities | join("；")),
        "外部判定机制：" + (.node.oracle | join("；")),
        "约束：" + (.node.constraints | if length == 0 then "遵循AGENTS.md和阶段规则" else join("；") end),
        "必需人工决定：" + (.node.humanGate.required_decisions // [] | if length == 0 then "无" else join("；") end),
        "完成后解锁：" + ([.unlocks[] | .id] | if length == 0 then "无" else join("；") end)
    '
}

review_session_cards() {
    local requested="${1:-}" json="${2:-false}" file file_rel node temporary
    local total checked pending invalid duplicates required_missing errors
    file="$(resolve_session_or_active "$requested")"
    file_rel="${file#$REPO_ROOT/}"
    node="$(session_workflow_node "$file")"
    temporary="$(mktemp)"
    trap 'rm -f -- "${temporary:-}"' RETURN
    session_card_rows "$file" >"$temporary"

    total="$(awk 'END { print NR + 0 }' "$temporary")"
    checked="$(awk -F '\t' '$3 == "1" { count++ } END { print count + 0 }' "$temporary")"
    pending=$((total - checked))
    invalid="$(awk -F '\t' '$3 == "1" && ($4 != "1" || $5 != "0") { count++ } END { print count + 0 }' "$temporary")"
    duplicates="$(cut -f1 "$temporary" | sed '/^$/d' | sort | uniq -d | wc -l)"
    required_missing=0
    while IFS= read -r required; do
        [[ -n "$required" ]] || continue
        if ! session_card_confirmed "$file" "$required"; then
            required_missing=$((required_missing + 1))
        fi
    done < <(required_decision_ids "$node")
    errors=$((invalid + duplicates + required_missing))

    if [[ "$json" == true ]]; then
        jq -Rn --arg session "$file_rel" --arg node "$node" \
            --argjson total "$total" --argjson checked "$checked" \
            --argjson pending "$pending" --argjson invalid "$invalid" \
            --argjson duplicates "$duplicates" --argjson required_missing "$required_missing" '
            [inputs | select(length > 0) | split("\t") | {
                id: .[0],
                kind: (if .[1] == "H" then "experience" elif .[1] == "D" then "decision" else "legacy-unresolved" end),
                checked: (.[2] == "1"),
                hasHumanConfirmation: (.[3] == "1"),
                hasPlaceholder: (.[4] == "1"),
                blocking: .[5],
                title: .[6],
                confirmation: .[7]
            }] as $cards
            | {
                session: $session,
                node: $node,
                summary: {
                    total: $total,
                    checked: $checked,
                    pending: $pending,
                    invalidChecked: $invalid,
                    duplicateIds: $duplicates,
                    missingRequiredDecisions: $required_missing
                },
                cards: $cards,
                validForHumanGate: (($invalid + $duplicates + $required_missing) == 0)
            }
        ' <"$temporary"
    else
        printf 'Session review: %s\nNode: %s\n' "$file_rel" "$node"
        if ((total == 0)); then
            printf '  No H/D/U cards found.\n'
        else
            while IFS=$'\t' read -r id kind is_checked has_confirmation has_placeholder blocking title confirmation; do
                : "$confirmation"
                local state='pending'
                if [[ "$is_checked" == 1 && "$has_confirmation" == 1 && "$has_placeholder" == 0 ]]; then
                    state='confirmed'
                elif [[ "$is_checked" == 1 ]]; then
                    state='invalid-confirmation'
                fi
                printf '  %s [%s] %s' "$id" "$state" "$title"
                [[ -n "$blocking" ]] && printf '  blocking=%s' "$blocking"
                printf '\n'
            done <"$temporary"
        fi
        printf 'Summary: total=%s checked=%s pending=%s invalid=%s duplicates=%s required-missing=%s\n' \
            "$total" "$checked" "$pending" "$invalid" "$duplicates" "$required_missing"
    fi

    ((errors == 0))
}

verify_workflow_node() {
    local node="$1" requested="${2:-}" json="${3:-false}" file file_rel bound_node
    local completeness=true coherence=true required_missing=0 missing_sections=0 oracle_count status
    require_workflow
    workflow_node_exists "$node" || die "workflow node not found: $node"
    file="$(resolve_session_or_active "$requested")"
    file_rel="${file#$REPO_ROOT/}"
    bound_node="$(session_workflow_node "$file")"
    [[ "$bound_node" == "$node" ]] || coherence=false

    local section
    for section in 证据 决策 验证 未解决 下一会话; do
        if ! section_has_content "$file" "$section"; then
            missing_sections=$((missing_sections + 1))
        fi
    done
    ((missing_sections == 0)) || completeness=false

    while IFS= read -r required; do
        [[ -n "$required" ]] || continue
        if ! session_card_confirmed "$file" "$required"; then
            required_missing=$((required_missing + 1))
        fi
    done < <(required_decision_ids "$node")
    ((required_missing == 0)) || completeness=false

    oracle_count="$(jq -r --arg node "$node" 'first(.nodes[] | select(.id == $node) | (.oracle // []) | length)' "$WORKFLOW_FILE")"
    status="$(workflow_node_status "$node")"

    if [[ "$json" == true ]]; then
        jq -n --arg node "$node" --arg status "$status" --arg session "$file_rel" \
            --argjson completeness "$completeness" --argjson coherence "$coherence" \
            --argjson missing_sections "$missing_sections" --argjson required_missing "$required_missing" \
            --argjson oracle_count "$oracle_count" '
            {
                node: $node,
                nodeStatus: $status,
                session: $session,
                completeness: {
                    passed: $completeness,
                    missingRequiredSections: $missing_sections,
                    missingRequiredDecisions: $required_missing
                },
                correctness: {
                    status: "requires-external-oracle-review",
                    oracleCount: $oracle_count,
                    agentSelfAssessmentIsSufficient: false
                },
                coherence: {
                    passed: $coherence,
                    sessionBoundToNode: $coherence
                },
                readyForHumanJudgment: ($completeness and $coherence)
            }
        '
    else
        printf 'Verification: %s\n' "$node"
        printf '  Completeness: %s (missing-sections=%s required-decisions=%s)\n' \
            "$completeness" "$missing_sections" "$required_missing"
        printf '  Correctness: requires external Oracle review (%s Oracle type(s)); Agent self-assessment is insufficient\n' "$oracle_count"
        printf '  Coherence: %s (Session node=%s)\n' "$coherence" "$bound_node"
        printf '  Human judgment required before accepted: yes\n'
    fi

    [[ "$completeness" == true && "$coherence" == true ]]
}

show_reconcile_context() {
    local requested="${1:-}" json="${2:-false}" file file_rel node
    file="$(resolve_session_or_active "$requested")"
    file_rel="${file#$REPO_ROOT/}"
    node="$(session_workflow_node "$file")"

    if [[ "$json" == true ]]; then
        jq -n --arg session "$file_rel" --arg node "$node" \
            --arg workflow "${WORKFLOW_FILE#$REPO_ROOT/}" --arg plan "${SESSION_PLAN#$REPO_ROOT/}" '
            {
                session: $session,
                node: $node,
                requiredReads: ["AGENTS.md", $workflow, $plan, $session],
                protocol: [
                    "Re-read every file from disk; conversation memory is not authoritative.",
                    "Identify human edits and their forward and backward impacts.",
                    "Separate facts, experience, decisions, evidence, and suggestions.",
                    "Show proposed changes one artifact at a time with rationale.",
                    "Write only changes explicitly approved by the human.",
                    "Never change WORKFLOW.json state or close the Session as part of reconciliation.",
                    "Record accepted and rejected proposals in the Session."
                ],
                candidateArtifacts: [
                    $session,
                    $workflow,
                    $plan,
                    ".problems/<problem-id>/README.md",
                    "manifests/source-baselines.yaml",
                    "docs/"
                ]
            }
        '
        return 0
    fi

    printf 'Reconciliation context\n'
    printf '  Session: %s\n  Node: %s\n' "$file_rel" "$node"
    printf '  Required reads: AGENTS.md, %s, %s, %s\n' \
        "${WORKFLOW_FILE#$REPO_ROOT/}" "${SESSION_PLAN#$REPO_ROOT/}" "$file_rel"
    printf 'Protocol:\n'
    printf '  1. Re-read files from disk; do not trust conversation memory.\n'
    printf '  2. Identify forward and backward impacts of human edits.\n'
    printf '  3. Show one artifact change and rationale at a time.\n'
    printf '  4. Write only after explicit human approval; preserve rejected proposals.\n'
    printf '  5. Do not transition workflow state or close the Session.\n'
}

show_retention_plan() {
    local requested="${1:-}" json="${2:-false}" file file_rel node
    file="$(resolve_session_or_active "$requested")"
    file_rel="${file#$REPO_ROOT/}"
    node="$(session_workflow_node "$file")"

    if [[ "$json" == true ]]; then
        jq --arg node "$node" --arg session "$file_rel" '
            first(.nodes[] | select(.id == $node)) as $target
            | {
                session: $session,
                node: $node,
                configuredTargets: ($target.retention_targets // []),
                categories: {
                    problemRecord: "状态、已接受结论、证据和下一步指针",
                    formalDocs: "已确认且需要长期维护的架构、接口和流程知识",
                    manifests: "可追溯来源、迁移关系、版本和制品组合",
                    verificationArtifacts: "命令、日志、报告、哈希和平台结果",
                    workflowOrCapability: "至少第二次真实复用并经过独立验证的控制或能力知识",
                    sessionOnly: "临时调查、被拒绝方案、未证实经验和中间日志"
                },
                writesAutomatically: false,
                requiresHumanApprovalPerTarget: true
            }
        ' "$WORKFLOW_FILE"
        return 0
    fi

    printf 'Retention plan\n  Session: %s\n  Node: %s\n' "$file_rel" "$node"
    printf '  Problem record: accepted state, conclusions, evidence pointers, next actions\n'
    printf '  docs/: confirmed architecture, interfaces, and durable process knowledge\n'
    printf '  manifests/: provenance, migration mapping, versions, artifact combinations\n'
    printf '  verification artifacts: commands, logs, reports, hashes, platform results\n'
    printf '  workflow/capability: only after a second real reuse and independent validation\n'
    printf '  Session only: temporary investigation, rejected options, unverified experience\n'
    printf 'No target file is modified; approve each promotion separately.\n'
}

append_session_card() {
    local kind="$1" title="$2" requested="${3:-}" file marker prefix label max next_id card temporary
    file="$(resolve_session_or_active "$requested")"
    session_has_status "$file" active || die "cards can only be appended to an active Session"
    [[ -n "$title" ]] || die "card title is required"

    case "$kind" in
        experience)
            marker='## 人工决策'
            prefix='H'
            label='人工经验'
            ;;
        decision)
            marker='## 证据'
            prefix='D'
            label='人工决策'
            ;;
        *) die "note kind must be experience or decision" ;;
    esac
    grep -Fqx -- "$marker" "$file" ||
        die "Session template does not contain required marker: $marker"

    max="$(awk -v prefix="$prefix" '
        $0 ~ ("^### " prefix "-[0-9]+") {
            id = $2
            sub("^" prefix "-", "", id)
            number = id + 0
            if (number > max) max = number
        }
        END { print max + 0 }
    ' "$file")"
    next_id="$(printf '%s-%03d' "$prefix" "$((max + 1))")"

    if [[ "$kind" == experience ]]; then
        card="### $next_id $title

- [ ] 用户已确认本条经验表达准确。
- 状态：\`submitted\`。
- 原始经验：待填写。
- 来源：待填写。
- 适用范围：待填写。
- 影响节点：待填写。
- 当前证据分类：\`Unknown\`。
- 处理建议：待填写。
- 人工确认记录：\`结论：待填写；确认人和时间：待填写\`。
"
    else
        card="### $next_id $title

- [ ] 用户已确认本项决定。
- 状态：\`proposed\`。
- 关联节点：待填写。
- 问题：待填写。
- 候选选项：待填写。
- 智能体建议：待填写。
- 支持证据：待填写。
- 反证和风险：待填写。
- 用户选择：待填写。
- 用户理由：待填写。
- 人工确认记录：\`确认人和时间：待填写\`。
"
    fi

    temporary="$(mktemp "$SESSION_DIR/.note.XXXXXX")"
    trap 'rm -f -- "${temporary:-}"' RETURN
    awk -v marker="$marker" -v card="$card" '
        $0 == marker && !inserted { print card; inserted = 1 }
        { print }
        END { if (!inserted) exit 1 }
    ' "$file" >"$temporary" || die "failed to insert $label card"
    chmod --reference="$file" "$temporary"
    mv -- "$temporary" "$file"
    temporary=''
    printf 'Added %s card %s to %s\n' "$label" "$next_id" "${file#$REPO_ROOT/}"
}


# Artifact-system overrides: derive views from contracts plus files on disk.

section_present() { grep -Fqx -- "## $2" "$1"; }

node_artifact_session() {
    local node="$1" requested="${2:-}" file
    if [[ -n "$requested" ]]; then
        file="$(resolve_session_file "$requested")"
        [[ "$(session_workflow_node "$file")" == "$node" ]] ||
            die "Session is not bound to workflow node: $node"
        printf '%s\n' "$file"
        return
    fi
    collect_active_sessions
    for file in "${ACTIVE_SESSIONS[@]}"; do
        if [[ "$(session_workflow_node "$file")" == "$node" ]]; then
            printf '%s\n' "$file"
            return
        fi
    done
    return 1
}

node_artifacts_json() {
    local node="$1" requested="${2:-}" session_file='' count temporary definition
    local artifact_id artifact_path path_source completion_type section node_status direct
    require_workflow
    count="$(jq -r --arg node "$node" \
        'first(.nodes[] | select(.id == $node) | (.artifacts // []) | length) // 0' \
        "$WORKFLOW_FILE")"
    ((count > 0)) || { printf '[]\n'; return; }

    if jq -e --arg node "$node" \
        'any(first(.nodes[] | select(.id == $node) | (.artifacts // []))[];
             .path_source == "active-session")' "$WORKFLOW_FILE" >/dev/null; then
        session_file="$(node_artifact_session "$node" "$requested")" ||
            die "node artifacts require an active or explicit Session: $node"
    fi

    node_status="$(workflow_node_status "$node")"
    temporary="$(mktemp)"
    trap 'rm -f -- "${temporary:-}"' RETURN

    while IFS= read -r definition; do
        artifact_id="$(jq -r '.id' <<<"$definition")"
        path_source="$(jq -r '.path_source // empty' <<<"$definition")"
        artifact_path="$(jq -r '.path // empty' <<<"$definition")"
        completion_type="$(jq -r '.completion.type' <<<"$definition")"
        direct=false
        if [[ "$path_source" == active-session ]]; then
            artifact_path="$session_file"
        elif [[ -n "$artifact_path" ]]; then
            artifact_path="$REPO_ROOT/$artifact_path"
        fi

        case "$completion_type" in
            file-nonempty)
                [[ -f "$artifact_path" && -s "$artifact_path" ]] && direct=true
                ;;
            section-present)
                section="$(jq -r '.completion.section' <<<"$definition")"
                [[ -f "$artifact_path" ]] &&
                    section_present "$artifact_path" "$section" && direct=true
                ;;
            section-nonempty)
                section="$(jq -r '.completion.section' <<<"$definition")"
                [[ -f "$artifact_path" ]] &&
                    section_has_content "$artifact_path" "$section" && direct=true
                ;;
            cards-confirmed)
                direct=true
                while IFS= read -r artifact_id; do
                    [[ -n "$artifact_id" ]] || continue
                    if [[ ! -f "$artifact_path" ]] ||
                       ! session_card_confirmed "$artifact_path" "$artifact_id"; then
                        direct=false
                    fi
                done < <(jq -r '.completion.card_ids[]?' <<<"$definition")
                ;;
            node-accepted)
                [[ "$node_status" == accepted ]] && direct=true
                ;;
            *)
                die "unsupported artifact completion type: $completion_type"
                ;;
        esac

        jq -n --argjson definition "$definition" --arg path "$artifact_path" \
            --argjson direct "$direct" '
            $definition + {
                resolved_path: (if $path == "" then null else $path end),
                content_present: $direct
            }
        ' >>"$temporary"
    done < <(jq -c --arg node "$node" \
        'first(.nodes[] | select(.id == $node) | (.artifacts // []))[]' \
        "$WORKFLOW_FILE")

    jq -s '
        . as $items
        | map(
            . as $item
            | ([($item.requires // [])[] as $dependency
                | ($items | any(.id == $dependency and .content_present))] | all) as $deps_ok
            | . + {
                dependencies_complete: $deps_ok,
                contract_complete: (.content_present and $deps_ok),
                missing_dependencies: [
                    (.requires // [])[] as $dependency
                    | select($items | all(.id != $dependency or (.content_present | not)))
                    | $dependency
                ],
                status: (
                    if ($deps_ok | not) then "blocked"
                    elif .content_present then
                        if .kind == "human-decision" then "confirmed"
                        elif .kind == "stable-input" then "available"
                        elif .kind == "verification" then "review-required"
                        else "complete" end
                    elif .kind == "promotion" then "promotion-pending"
                    else "ready" end
                )
            }
        )
        | . as $resolved
        | map(
            . as $target
            | . + {impacted_by: [
                $resolved[]
                | select((.impacts // []) | index($target.id))
                | .id
            ]}
        )
    ' "$temporary"
}

required_decision_ids() {
    jq -r --arg node "$1" '
        first(.nodes[] | select(.id == $node)) as $target
        | [($target.artifacts // [])[]
            | select(.kind == "human-decision")
            | .completion.card_ids[]?]
        | if length > 0 then .[]
          else ($target.human_gate.required_decisions // [])[]? end
    ' "$WORKFLOW_FILE"
}

validate_required_decisions() {
    local node="$1" decision_record="$2" required
    [[ -n "$decision_record" ]] || return
    while IFS= read -r required; do
        [[ -n "$required" ]] || continue
        session_card_confirmed "$decision_record" "$required" ||
            die "required human decision is missing, unchecked, or incomplete: $required"
    done < <(required_decision_ids "$node")
}

validate_node_contract_ready() {
    local node="$1" required legacy count
    required="$(jq -r --arg node "$node" \
        'first(.nodes[] | select(.id == $node) |
          .artifact_contract.required_before_ready) // false' "$WORKFLOW_FILE")"
    [[ "$required" == true ]] || return
    legacy="$(jq -r --arg node "$node" \
        'first(.nodes[] | select(.id == $node) |
          .artifact_contract.legacy_accepted) // false' "$WORKFLOW_FILE")"
    [[ "$legacy" == true ]] && return
    count="$(jq -r --arg node "$node" \
        'first(.nodes[] | select(.id == $node) | (.artifacts // []) | length) // 0' \
        "$WORKFLOW_FILE")"
    ((count > 0)) || die "workflow node has no artifact contract: $node"
}

validate_node_artifacts_for_acceptance() {
    local node="$1" requested="${2:-}" required artifacts
    required="$(jq -r --arg node "$node" \
        'first(.nodes[] | select(.id == $node) |
          .artifact_contract.acceptance_requires_complete) // false' "$WORKFLOW_FILE")"
    [[ "$required" == true ]] || return
    artifacts="$(node_artifacts_json "$node" "$requested")"
    if ! jq -e 'all(.[]; ((.required // false) | not) or .contract_complete)' \
        <<<"$artifacts" >/dev/null; then
        jq -r '.[] |
            select((.required // false) and (.contract_complete | not)) |
            "incomplete artifact: \(.id) status=\(.status) missing=[\(.missing_dependencies | join(","))]"' \
            <<<"$artifacts" >&2
        die "required workflow artifacts are incomplete: $node"
    fi
}


enriched_workflow_json() {
    local temporary next node artifacts
    temporary="$(mktemp)"
    trap 'rm -f -- "${temporary:-}"' RETURN
    cp -- "$WORKFLOW_FILE" "$temporary"
    while IFS= read -r node; do
        artifacts="$(node_artifacts_json "$node")"
        next="$(mktemp)"
        jq --arg node "$node" --argjson artifacts "$artifacts" '
            .nodes |= map(
                if .id == $node then
                    .artifact_status = $artifacts
                    | .artifact_summary = {
                        total: ($artifacts | length),
                        required: ([$artifacts[] | select(.required // false)] | length),
                        required_complete: ([$artifacts[] | select((.required // false) and .contract_complete)] | length),
                        complete: ([$artifacts[] | select(.contract_complete)] | length),
                        required_incomplete: ([
                            $artifacts[]
                            | select((.required // false) and (.contract_complete | not))
                        ] | length),
                        ready: ([$artifacts[] | select(.status == "ready")] | length),
                        blocked: ([$artifacts[] | select(.status == "blocked")] | length)
                    }
                else . end
            )
        ' "$temporary" >"$next"
        mv -- "$next" "$temporary"
    done < <(jq -r '.nodes[].id' "$WORKFLOW_FILE")
    cat "$temporary"
}

show_workflow_status() {
    local json="${1:-false}" active='' active_rel='' enriched
    collect_active_sessions
    if (("${#ACTIVE_SESSIONS[@]}" == 1)); then
        active="${ACTIVE_SESSIONS[0]}"
        active_rel="${active#$REPO_ROOT/}"
    fi
    enriched="$(enriched_workflow_json)"

    if [[ "$json" == true ]]; then
        jq --arg active "$active_rel" '
            .nodes as $nodes
            | {
                workflowId: .workflow_id,
                problemId: .problem_id,
                state: .state,
                artifactModel: .artifact_model,
                activeSession: (if $active == "" then null else $active end),
                nodes: [
                    $nodes[] as $node
                    | {
                        id: $node.id,
                        title: $node.title,
                        phase: $node.phase,
                        status: $node.status,
                        artifactSummary: $node.artifact_summary,
                        artifacts: ($node.artifact_status // []),
                        missingDependencies: [
                            ($node.depends_on // [])[] as $dependency
                            | select(any($nodes[];
                                .id == $dependency and .status != "accepted"))
                            | $dependency
                        ],
                        requiredDecisions: [
                            ($node.artifacts // [])[]
                            | select(.kind == "human-decision")
                            | .completion.card_ids[]?
                        ],
                        nextAction: (
                            if $node.status == "planned" and
                               (($node.artifacts // []) | length) == 0
                                then "define-artifact-contract"
                            elif $node.status == "ready" then "start"
                            elif $node.status == "active" and
                                 ($node.artifact_summary.required_incomplete // 0) > 0
                                then "complete-required-artifacts"
                            elif $node.status == "active"
                                then "verify-and-request-human-judgment"
                            elif $node.status == "verifying"
                                then "verify-and-transition"
                            else null end
                        )
                    }
                ]
            }
        ' <<<"$enriched"
        return
    fi

    jq -r '
        "Workflow: \(.workflow_id) state=\(.state)",
        "",
        "STATUS\tPHASE\tNODE\tARTIFACTS\tTITLE",
        (.nodes[] |
            "\(.status)\t\(.phase)\t\(.id)\t\(.artifact_summary.required_complete // 0)/\(.artifact_summary.required // 0)\t\(.title)"),
        "",
        (.nodes[]
            | select((.artifact_status // []) | length > 0)
            | "Artifacts for \(.id):",
              (.artifact_status[] |
                "  \(.id): \(.status)"
                + (if (.missing_dependencies | length) == 0 then ""
                   else " missing=[" + (.missing_dependencies | join(",")) + "]" end)))
    ' <<<"$enriched"
    printf '\nActive Session: %s\n' "${active_rel:-none}"
}

show_node_instructions() {
    local node="$1" json="${2:-false}" active_rel='' artifacts
    workflow_node_exists "$node" || die "workflow node not found: $node"
    if active_rel="$(node_artifact_session "$node" 2>/dev/null)"; then
        active_rel="${active_rel#$REPO_ROOT/}"
    else
        active_rel=''
    fi
    artifacts="$(node_artifacts_json "$node")"

    if [[ "$json" == true ]]; then
        jq --arg node "$node" --arg active "$active_rel" \
            --argjson artifacts "$artifacts" '
            .nodes as $nodes
            | first($nodes[] | select(.id == $node)) as $target
            | {
                workflowId: .workflow_id,
                problemId: .problem_id,
                knowledgeLayers: .artifact_model.knowledge_layers,
                node: {
                    id: $target.id,
                    title: $target.title,
                    phase: $target.phase,
                    status: $target.status,
                    requiredCapabilities: ($target.required_capabilities // []),
                    oracle: ($target.oracle // []),
                    constraints: ($target.constraints // []),
                    humanGate: $target.human_gate
                },
                artifacts: $artifacts,
                nextArtifacts: [
                    $artifacts[] | select(.status == "ready") | .id
                ],
                blockedArtifacts: [
                    $artifacts[]
                    | select(.status == "blocked")
                    | {id, missingDependencies: .missing_dependencies}
                ],
                nodeDependencies: [
                    ($target.depends_on // [])[] as $dependency
                    | first($nodes[] | select(.id == $dependency))
                    | {id, title, status}
                ],
                activeSession: (if $active == "" then null else $active end),
                executionRules: {
                    rereadFromDisk: true,
                    workFromResolvedArtifactPaths: true,
                    dependencyOrderIsContextNotAcceptance: true,
                    fileExistenceIsNotCompletion: true,
                    updateImpactsAreBidirectional: true,
                    agentCannotAcceptHumanGate: true
                }
            }
        ' "$WORKFLOW_FILE"
        return
    fi

    show_node_instructions "$node" true | jq -r '
        "Node: \(.node.id) (\(.node.title))",
        "Phase/status: \(.node.phase) / \(.node.status)",
        "Session: \(.activeSession // "none")",
        "Artifacts:",
        (.artifacts[] |
            "  \(.id) [\(.kind)] \(.status) -> \(.resolved_path // "none")"),
        "Next: " + (.nextArtifacts |
            if length == 0 then "none" else join("; ") end),
        "Blocked: " + ([.blockedArtifacts[].id] |
            if length == 0 then "none" else join("; ") end)
    '
}


verify_workflow_node() {
    local node="$1" requested="${2:-}" json="${3:-false}"
    local file file_rel bound artifacts incomplete required total oracle_count
    local coherence=true
    file="$(node_artifact_session "$node" "$requested")"
    file_rel="${file#$REPO_ROOT/}"
    bound="$(session_workflow_node "$file")"
    [[ "$bound" == "$node" ]] || coherence=false
    artifacts="$(node_artifacts_json "$node" "$file")"
    incomplete="$(jq '[
        .[] | select((.required // false) and (.contract_complete | not))
    ] | length' <<<"$artifacts")"
    required="$(jq '[.[] | select(.required // false)] | length' <<<"$artifacts")"
    total="$(jq 'length' <<<"$artifacts")"
    oracle_count="$(jq --arg node "$node" --argjson artifacts "$artifacts" '
        [
            (first(.nodes[] | select(.id == $node) | (.oracle // []))[]?),
            ($artifacts[] | (.oracle // [])[]?)
        ] | unique | length
    ' "$WORKFLOW_FILE")"

    if [[ "$json" == true ]]; then
        jq -n --arg node "$node" --arg session "$file_rel" \
            --argjson artifacts "$artifacts" \
            --argjson coherence "$coherence" \
            --argjson total "$total" \
            --argjson required "$required" \
            --argjson incomplete "$incomplete" \
            --argjson oracles "$oracle_count" '
            {
                node: $node,
                session: $session,
                artifacts: $artifacts,
                completeness: {
                    passed: ($incomplete == 0),
                    totalArtifacts: $total,
                    requiredArtifacts: $required,
                    incompleteRequiredArtifacts: $incomplete
                },
                correctness: {
                    status: "requires-external-oracle-and-human-review",
                    oracleCount: $oracles,
                    agentSelfAssessmentIsSufficient: false
                },
                coherence: {
                    passed: $coherence,
                    sessionBoundToNode: $coherence,
                    artifactDependenciesChecked: true
                },
                readyForHumanJudgment: (($incomplete == 0) and $coherence),
                accepted: false
            }
        '
    else
        printf 'Verification: %s\n' "$node"
        printf '  Required artifacts complete: %s/%s\n' \
            "$((required - incomplete))" "$required"
        jq -r '.[] | "    \(.id): \(.status)"' <<<"$artifacts"
        printf '  Correctness: external Oracle and human review required\n'
        printf '  Coherence: %s\n' "$coherence"
        printf '  Accepted: no\n'
    fi
    ((incomplete == 0)) && [[ "$coherence" == true ]]
}

show_reconcile_context() {
    local requested="${1:-}" json="${2:-false}" selected="${3:-}"
    local file file_rel node artifacts
    file="$(resolve_session_or_active "$requested")"
    file_rel="${file#$REPO_ROOT/}"
    node="$(session_workflow_node "$file")"
    artifacts="$(node_artifacts_json "$node" "$file")"
    if [[ -n "$selected" ]]; then
        jq -e --arg id "$selected" 'any(.[]; .id == $id)' \
            <<<"$artifacts" >/dev/null ||
            die "artifact not found for node $node: $selected"
    fi

    if [[ "$json" == true ]]; then
        jq -n --arg session "$file_rel" --arg node "$node" \
            --arg selected "$selected" --argjson artifacts "$artifacts" '
            ($artifacts | map({
                key: .id,
                value: {
                    status: .status,
                    path: .resolved_path,
                    requires: .requires,
                    impacts: (.impacts // []),
                    impactedBy: (.impacted_by // [])
                }
            }) | from_entries) as $graph
            | {
                session: $session,
                node: $node,
                selectedArtifact: (
                    if $selected == "" then null else $selected end
                ),
                artifactGraph: $graph,
                impact: (
                    if $selected == "" then {
                        mode: "full-graph",
                        forward: [],
                        backward: []
                    } else {
                        mode: "selected-artifact",
                        forward: ($graph[$selected].impacts // []),
                        backward: ($graph[$selected].impactedBy // [])
                    } end
                ),
                protocol: [
                    "Re-read selected and related artifacts from disk.",
                    "Classify the edit before changing another artifact.",
                    "Check impacts in both dependency directions.",
                    "Propose revisions per existing artifact with causal rationale.",
                    "Write only revisions explicitly approved by the human.",
                    "Do not create missing artifacts, transition state, retain knowledge, or close the Session."
                ]
            }
        '
        return
    fi

    show_reconcile_context "$requested" true "$selected" | jq -r '
        "Reconciliation context",
        "  Session: \(.session)",
        "  Selected: \(.selectedArtifact // "full graph")",
        "  Backward: " + (.impact.backward |
            if length == 0 then "none" else join("; ") end),
        "  Forward: " + (.impact.forward |
            if length == 0 then "none" else join("; ") end)
    '
}

show_retention_plan() {
    local requested="${1:-}" json="${2:-false}"
    local file file_rel node artifacts node_status
    file="$(resolve_session_or_active "$requested")"
    file_rel="${file#$REPO_ROOT/}"
    node="$(session_workflow_node "$file")"
    node_status="$(workflow_node_status "$node")"
    artifacts="$(node_artifacts_json "$node" "$file")"

    if [[ "$json" == true ]]; then
        jq -n --arg session "$file_rel" --arg node "$node" \
            --arg node_status "$node_status" --argjson artifacts "$artifacts" '
            {
                session: $session,
                node: $node,
                nodeStatus: $node_status,
                promotions: [
                    $artifacts[]
                    | select(.kind == "promotion")
                    | {
                        id,
                        title,
                        source: .resolved_path,
                        requires,
                        targets: (.targets // []),
                        ready: (
                            .contract_complete and
                            $node_status == "accepted"
                        ),
                        status,
                        rules: (.rules // [])
                    }
                ],
                writesAutomatically: false,
                requiresHumanApprovalPerTarget: true,
                closeIsNotRetention: true
            }
        '
        return
    fi

    show_retention_plan "$requested" true | jq -r '
        "Retention plan",
        "  Session: \(.session)",
        "  Node/status: \(.node) / \(.nodeStatus)",
        (.promotions[] |
            "  \(.id): ready=\(.ready)",
            (.targets[] | "    -> \(.path): \(.content)")),
        "No target is modified."
    '
}
