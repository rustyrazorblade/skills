## ADDED Requirements

### Requirement: Every owner question follows one four-part format
The **Presenting to the owner** section of `docs/workflow.md` SHALL define one question format.  The format SHALL have four parts, in this order: (1) the decision, as the first line, in one plain sentence; (2) what each referenced item is; (3) why the decision comes up now, in one or two sentences; (4) the options.  Every question an agent puts to the owner SHALL follow it.

#### Scenario: A reader opens the contract
- **WHEN** a reader opens **Presenting to the owner** in `docs/workflow.md`
- **THEN** it defines the question format with its four parts in the order above
- **AND** it holds one worked example, the backlog-hit question about 928 and 971 rewritten to the format

#### Scenario: The decision is buried in an option
- **WHEN** an agent drafts a question whose first line is not the decision
- **THEN** the draft does not meet the format, and the agent rewrites it so the decision is the first line

### Requirement: A live question uses the menu picker, with the recommended option first
When an agent asks the owner a question live in the session, it SHALL ask it with the menu picker (the `AskUserQuestion` tool), one question per call.  The recommended option SHALL be listed first, and its label SHALL end with "(Recommended)", so the owner can press Enter to choose it.  The question text SHALL carry the decision and why it comes up now.  Each option's description SHALL carry its effect, pros, cons, and tradeoff.  When the picker cannot hold the question, because it has more options than the picker allows, the agent SHALL ask it in plain text in the same format.  A written question, on an issue or a PR, is not affected.

#### Scenario: A live question with a recommendation
- **WHEN** an agent asks the owner a question live in the session
- **THEN** it calls the menu picker with that one question, the recommended option first with a label ending "(Recommended)", and each option's description stating its effect, pros, cons, and tradeoff

#### Scenario: The owner presses Enter
- **WHEN** the picker is shown and the owner presses Enter without moving the selection
- **THEN** the recommended option is chosen

#### Scenario: Too many options for the picker
- **WHEN** a live question has more options than the picker can hold
- **THEN** the agent asks it in plain text, in the same format, with exactly one option marked as recommended

#### Scenario: A written question
- **WHEN** an agent posts a question as an issue comment
- **THEN** the picker rule does not apply, and the comment follows the written-question rules

### Requirement: A referenced issue or PR is described, not just named
When a question names an issue or a PR, it SHALL give `<number>: <title>`, the filing date, the author, and one line on why the item exists.  When the agent created the item in this session, the question SHALL say so.

#### Scenario: A question names an older issue
- **WHEN** a question names issue 928, filed three weeks ago by the owner
- **THEN** it gives `928: <title>`, the filing date, the author, and one line on why 928 exists

#### Scenario: A question names an issue the agent just filed
- **WHEN** a question names an issue the agent created in this session
- **THEN** the question says the agent created it in this session

### Requirement: The format covers live and written questions
The contract SHALL state that the format covers live questions in the session, questions written into issue comments, questions written into PR bodies, and `needs-attention` comments.

#### Scenario: A reader checks what the format applies to
- **WHEN** a reader checks the contract for what the format covers
- **THEN** it names live questions in the session, issue comments, PR bodies, and `needs-attention` comments explicitly

### Requirement: A question passes the pre-send check
The contract SHALL hold this check, word for word: "Could the owner answer this after switching tabs, with no other context, and without opening a file or a link?"  When the answer is no, the agent SHALL rewrite the question before it sends it.

#### Scenario: The check is in the contract
- **WHEN** a reader opens the contract
- **THEN** the pre-send check appears word for word

#### Scenario: A question fails the check
- **WHEN** a draft question needs the owner to open a link to understand it
- **THEN** the agent rewrites it before sending it

### Requirement: Process vocabulary is banned in questions
A question SHALL NOT use the terms overlap, dependency link, seam, fast path, lens, or stop, unless the same sentence says in plain words what the term does.  The contract SHALL list these terms.

#### Scenario: A reader checks the ban
- **WHEN** a reader opens the contract
- **THEN** it bans process vocabulary and lists overlap, dependency link, seam, fast path, lens, and stop

#### Scenario: A question uses a banned term alone
- **WHEN** a draft question says "record a dependency link to 928" with no plain explanation
- **THEN** the agent rewrites it to say what happens, for example "mark 928 as unable to land before this issue"

### Requirement: The existing presentation rules stay in force
The rewritten contract SHALL keep, at full strength: plain terms before any identifier, with an identifier only as a trailing tag; a marked recommendation; and `<number>: <title>` on its own `-` line.  The contract SHALL state the `<number>: <title>` rule itself.  The copies of that rule in skill and agent files SHALL stay, each with a pointer to the format beside it.

#### Scenario: A reader checks the existing rules
- **WHEN** a reader compares the rewritten contract with the rules it had before this change
- **THEN** the plain-terms rule, the marked recommendation, and the `-` line citation are all there, and none is weaker

#### Scenario: A skill's own citation rule
- **WHEN** a reader opens a skill's Rules section that states the `<number>: <title>` rule
- **THEN** the rule is still there, with a pointer to the question format beside it

### Requirement: Every place that asks the owner points to the format and holds no copy
Every in-scope file that tells an agent to ask the owner something, live or in writing, SHALL point to the question format in `docs/workflow.md`.  No such file SHALL hold its own copy of the four-part format.  The in-scope files are at least `docs/workflow.md`, `agents/issue-manager.md`, `agents/project-manager.md`, `agents/product-manager.md`, `agents/architect.md`, `skills/activate/SKILL.md` (steps 1, 4 and 7), `skills/groom/SKILL.md`, `skills/setup/SKILL.md`, `skills/address/SKILL.md`, `skills/implement/SKILL.md`, and every `needs-attention` or escalation instruction.

#### Scenario: A reader checks an in-scope file
- **WHEN** a reader opens an in-scope file at a place where it tells an agent to ask the owner something
- **THEN** that place points to the question format in `docs/workflow.md`

#### Scenario: A reader searches for copies
- **WHEN** a reader searches the plugin outside `docs/workflow.md` for the four parts of the format
- **THEN** no file restates them

### Requirement: needs-attention comments and escalations follow the format
The instruction for every `🆘 Needs attention:` comment and every escalation SHALL point to the format.  The first line of a needs-attention question SHALL be `🆘 Needs attention: Question k of n: <the decision, in one plain sentence>`.

#### Scenario: implement stops on a failed gate
- **WHEN** `implement` writes a `🆘 Needs attention:` comment
- **THEN** the instruction for that comment points to the format, and the comment asks one question in it

#### Scenario: Open questions at a draft PR
- **WHEN** `implement` leaves a draft PR with questions still open
- **THEN** the instruction points to the format, and the questions are asked on the issue, not in the PR body

### Requirement: product-manager and architect draft questions in the format
The prompts of `product-manager` and `architect` SHALL tell each agent to follow the question format for any question or list of options it drafts for the owner.

#### Scenario: product-manager returns questions
- **WHEN** `product-manager` returns a question for `groom` to relay
- **THEN** its prompt told it to write the question in the format, so the question arrives complete

#### Scenario: architect returns design options
- **WHEN** `architect` returns a set of options for the design stop
- **THEN** its prompt told it to write each option with its effect, pros, cons, and tradeoff, and to mark one as recommended

### Requirement: setup and the design stop ask about each item in its own message
`setup` SHALL show its check results as information and SHALL ask about each item that needs an answer in its own message.  `activate` step 4 SHALL ask about each design choice and each debt item in its own message.

#### Scenario: setup finds three missing prerequisites
- **WHEN** `setup` step 1 finds three prerequisites missing
- **THEN** it shows the check results, lists the three items as bullets, and asks about each one in its own message

#### Scenario: The design stop has two choices and one debt item
- **WHEN** `activate` step 4 has two design choices and one debt item for the owner
- **THEN** it asks about each of the three in its own message

### Requirement: Seam 1 asks about each override and conflict in its own message
Each entry in `overrides.md` SHALL have a stable heading and, once answered, a committed `**Owner answer:**` line.  The entries without an answer line are the pending questions.  The Seam 1 comment SHALL show the spec as information, list the pending questions as bullets, and ask only the first.  Each later entry SHALL be its own question, and the last question SHALL be whether to approve the plan.  An answer of "keep the existing behavior" SHALL be recorded as a redirect, and the plan SHALL be regenerated once, after every entry is answered, keeping the answers on entries the regeneration did not change.  `.spec-flow/seam1-last-shown-sha` SHALL be written only after the final approve question is asked.  Under auto-approve, the agent SHALL answer each entry "accept as written" and commit that answer.  A hard conflict SHALL still always stop for the owner.

#### Scenario: A spec with two overrides
- **WHEN** Seam 1 renders a spec whose `overrides.md` has two unanswered entries
- **THEN** the comment shows the spec, lists both entries and the final approve question as bullets, and asks only about the first entry

#### Scenario: The owner keeps the existing behavior on one entry
- **WHEN** the owner answers one entry "keep the existing behavior"
- **THEN** the answer is committed as a redirect, the next entry is asked, and the plan is regenerated once after the last entry is answered

#### Scenario: A resumed session with pending entries
- **WHEN** the session resumes and one entry still has no answer
- **THEN** the agent asks that entry, and `.spec-flow/seam1-last-shown-sha` is still unwritten

#### Scenario: Auto-approve with no hard conflict
- **WHEN** the owner instructions auto-approve the spec and no entry is a hard conflict
- **THEN** the agent commits "accept as written" as each entry's answer and proceeds

#### Scenario: Auto-approve with a hard conflict
- **WHEN** the owner instructions auto-approve the spec and one entry is a hard conflict
- **THEN** Seam 1 stops for the owner on that entry

### Requirement: No hard-coded limit on questions
No skill or agent SHALL cap the number of questions an agent may ask the owner in a conversation, in a stage, or in a round.  The five-question cap in `activate` step 1 SHALL be removed.  The "at most three questions per round" limit in `skills/groom/SKILL.md` and `agents/product-manager.md` SHALL be removed, including from each file's description.

#### Scenario: Step 1 has seven questions
- **WHEN** `activate` step 1 has seven questions for the owner
- **THEN** it lists all seven and asks each one in turn

#### Scenario: A reader searches for a question limit
- **WHEN** a reader searches `skills/groom/SKILL.md`, `agents/product-manager.md`, `skills/activate/SKILL.md`, and the rest of the plugin for a number that caps how many questions reach the owner
- **THEN** none exists, including "at most three per round", "up to three questions", and "up to five"

### Requirement: The briefing comes first, in the same turn as the first question
When the owner returns to the session, or after a review has run, the agent SHALL send, in one turn: the briefing and the bullet list of upcoming questions, then a horizontal rule, then the first question.  Later questions in the same series SHALL carry no briefing.  Each question SHALL still carry the format's parts 2 and 3.

#### Scenario: The owner attaches to a waiting session
- **WHEN** the owner attaches to an `issue-manager` that has three questions pending
- **THEN** the turn shows the briefing and the three questions as bullets, a horizontal rule, and the first question

#### Scenario: The second question in a series
- **WHEN** the owner answers the first question and the agent asks the second
- **THEN** the second question carries no briefing, and still says what its referenced items are and why it comes up now

### Requirement: Written questions live on the issue thread
A written question SHALL be posted only as an issue comment.  The comment SHALL say "Question k of n", list all n questions as bullets, ask only question k in the format, and end with "Reply here; the next question follows when the session resumes."  A PR body SHALL carry information only, plus the line "Questions about this PR are on the issue."  The next question SHALL go where the owner answered.  The agent SHALL confirm each answer with a comment "✅ Question k answered: <the answer in one line>".  An unclear reply SHALL get one confirm question before anything is recorded.  The `needs-attention` label SHALL stay until the last question in its series is answered.  No agent SHALL poll for replies.

#### Scenario: Three questions for an absent owner
- **WHEN** an agent has three questions and the owner is not in the session
- **THEN** it posts one issue comment that says "Question 1 of 3", lists all three, asks only the first, and ends with "Reply here; the next question follows when the session resumes."

#### Scenario: The owner answers on GitHub
- **WHEN** the owner replies to question 1 on the issue, and the `issue-manager` next runs
- **THEN** it posts "✅ Question 1 answered: …" and posts question 2 as a new comment, and also asks it in the session

#### Scenario: The owner answers in the session
- **WHEN** the owner answers question 1 in the session
- **THEN** the agent asks question 2 in the session

#### Scenario: A PR body at a draft stop
- **WHEN** `implement` writes a PR body while questions are open
- **THEN** the body holds no question and includes "Questions about this PR are on the issue."

#### Scenario: A needs-attention series
- **WHEN** a needs-attention series has two questions and the owner answers the first
- **THEN** the `needs-attention` label stays until the second is answered

## MODIFIED Requirements

### Requirement: One question per message, with no exceptions
An agent SHALL put at most one question to the owner in a message, live or written.  Anything that needs the owner's decision SHALL be its own message.  When an agent has several questions, it SHALL first list them all as bullets, for context, and then ask them one per message.  An agent MAY show a list of items only when nothing in it needs an answer.  No file in the plugin SHALL allow several questions in one message, and the owner SHALL NOT be offered a batch.

#### Scenario: An agent has several questions
- **WHEN** an agent has four questions for the owner
- **THEN** it lists all four as bullets, then asks the first, and asks the next only after the owner answers

#### Scenario: A reader searches for an exception
- **WHEN** a reader searches `docs/workflow.md`, `skills/groom/SKILL.md`, `skills/setup/SKILL.md`, `skills/activate/SKILL.md`, and the rest of the plugin for a rule that allows several questions in one message
- **THEN** none exists, including a rule that lets the owner override to a batch

#### Scenario: The board shows many issues
- **WHEN** the board renders many issues at once
- **THEN** that is allowed, because nothing in it needs an answer

#### Scenario: Unresolved fix-loop findings
- **WHEN** `implement` or `address` has three unresolved findings that each need the owner's decision
- **THEN** each finding is its own question, and the findings list in the PR body is information only

### Requirement: Each option states its effect, pros, cons, and tradeoff, and exactly one is recommended
When a question lists options, each option SHALL state its concrete effect, its pros, its cons, and the tradeoff the choice makes.  Exactly one option SHALL be marked as recommended.  The contract SHALL NOT allow an agent to withhold a recommendation.

#### Scenario: An option states only its effect
- **WHEN** an option says what happens but gives no pros, cons, or tradeoff
- **THEN** the option does not meet the format

#### Scenario: An option states only a cost
- **WHEN** an option states a cost but not its concrete effect
- **THEN** the option does not meet the format

#### Scenario: A choice the agent thinks is pure preference
- **WHEN** an agent presents options for a choice it considers the owner's preference
- **THEN** it still marks exactly one option as recommended

### Requirement: Plain terms and one question per message apply to live and written presentations
The plain-terms rules SHALL apply to every presentation, whether interactive or written into an artifact such as a PR body or an issue comment.  The one-question-per-message rule SHALL apply to written questions as well as to live turns: a written question is posted on the issue thread, one question per comment.  A written list that needs no answer, such as a residual findings list in a PR body, is information and is not split.

#### Scenario: A finding written into a PR body
- **WHEN** an agent writes residual findings into a PR body
- **THEN** each finding is stated in plain terms with the identifier as a trailing tag
- **AND** the list is information only, and any finding that needs the owner's decision is asked on the issue, one question per comment

### Requirement: Every owner-facing presenter is bound
Every agent or skill that presents findings, options, or questions to the owner SHALL follow this contract.  The bound presenters are `issue-manager`, `implement`, `address`, `activate`, `groom`, `setup`, and `project-manager`.  `product-manager` and `architect` SHALL follow the question format for any question or list of options they draft for the owner, even though a relayer presents it.  A review subagent that returns structured output to a relayer, and never drafts a question for the owner, is not bound.

#### Scenario: The central coordinator presents a decision
- **WHEN** `project-manager` asks the owner which issue to start next
- **THEN** it follows the contract, the same as any other bound presenter

#### Scenario: A review subagent returns findings to its lead
- **WHEN** a lens returns findings tagged with identifiers to its lead agent
- **THEN** the identifiers are correct on that agent-to-agent channel and are not changed by this contract

## REMOVED Requirements

### Requirement: The owner may override to a batch
**Reason**: The owner never wants a batch.  Every question is its own message, and the owner is never offered a set at once.
**Migration**: None; there is no replacement.  "One question per message, with no exceptions" forbids any rule that lets the owner override to a batch.

### Requirement: Deliberate batch presentations are exempt
**Reason**: A list is allowed only when nothing in it needs an answer.  The exemption let `groom`'s bulk assumption confirm and the Seam 1 tables act as a batch of questions.
**Migration**: The board, `setup`'s check results, the rendered spec at Seam 1, and a residual findings list stay allowed as information under "One question per message, with no exceptions".  `groom` asks about each assumption in its own message (`idea-refinement`: "Assumptions are confirmed one at a time, split by provenance").  Seam 1 asks about each override and conflict in its own message ("Seam 1 asks about each override and conflict in its own message").

## RENAMED Requirements

- FROM: `### Requirement: Decisions are presented one at a time by default`
- TO: `### Requirement: One question per message, with no exceptions`
- FROM: `### Requirement: Options state their cost, and the recommended one is marked where one exists`
- TO: `### Requirement: Each option states its effect, pros, cons, and tradeoff, and exactly one is recommended`
- FROM: `### Requirement: Plain terms apply to written artifacts; one-at-a-time applies to live turns`
- TO: `### Requirement: Plain terms and one question per message apply to live and written presentations`
