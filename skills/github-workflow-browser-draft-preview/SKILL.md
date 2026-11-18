---
name: github-workflow-browser-draft-preview
description: |
  Load before writing GitHub text that people other than the user will
  read: a new PR or issue, a comment or review reply, or an edit to a PR
  body or comment, even unasked. The GitHub part of
  `coding-agent-draft-in-browser`, loaded with it: drafted in the user's
  browser, in GitHub's Preview, for the user to send. Not for a PR that
  mirrors its commit unless the user wants it rendered.
tags: [agent, workflow, interactive]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
  - mcp__claude-in-chrome__tabs_context_mcp
  - mcp__claude-in-chrome__tabs_create_mcp
  - mcp__claude-in-chrome__tabs_close_mcp
  - mcp__claude-in-chrome__navigate
  - mcp__claude-in-chrome__find
  - mcp__claude-in-chrome__read_page
  - mcp__claude-in-chrome__form_input
  - mcp__claude-in-chrome__computer
  - mcp__claude-in-chrome__javascript_tool
---

# Draft GitHub text in the browser

_Write the draft where it will be posted, show it rendered in GitHub's own Preview with the part to read boxed in red, bring it to the front, and leave it for the user to send._

`coding-agent-draft-in-browser` owns when text is drafted in the browser
(whenever people other than the user will read it), keeping personal
details out of public drafts, and the rule that only the user sends.
This skill is its GitHub part: the surfaces, their editors, Preview and
the red box.

Load it before the first Claude in Chrome call of a GitHub drafting task,
together with `coding-agent-draft-in-browser`, `chrome-browser`, which
covers loading the browser tools
in one `ToolSearch` call and working in a new tab, and
`coding-agent-browser-selection`, which makes sure the session drives the
user's preferred browser. This skill only drafts: it never clicks a
submit button, and never sends the text another way, such as with `gh`.

For a PR that should mirror a commit (`github-hygiene-pull-request-mirrors-commit`),
that skill's script is the default. Use this one when the user wants to
see or adjust the rendered text before it is sent.

## The bundled scripts

Both scripts sit in `scripts/` beside this `SKILL.md`
(`~/.claude/skills/github-workflow-browser-draft-preview/scripts/` for a
user install). `focus-chrome-tab.sh` is run with Bash.
`highlight-preview.js` is not run directly: Read it and pass its text to
`javascript_tool`.

## The draft surfaces

| Draft                     | Open this URL                                                    | Editor                                                         |
| ------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------- |
| New pull request          | `https://github.com/{owner}/{repo}/compare/{base}...{head}?expand=1` | the title field and the description editor                     |
| Issue or PR comment       | the issue or PR page                                             | the "Add a comment" editor at the bottom                       |
| Reply to a review thread  | the PR's Files changed or Conversation tab                       | the thread's "Reply" box                                       |
| Edit a PR body or comment | the issue or PR page                                             | the comment's `…` menu → Edit, which opens it in an editor     |
| New issue                 | `https://github.com/{owner}/{repo}/issues/new`                   | the title field and the description editor                     |

Fill the editors by typing: never put the draft text in URL query
parameters, even where GitHub accepts `title=` and `body=`.

## The procedure

1. **Open the surface** in a new tab in the Claude in Chrome tab group
   (`tabs_context_mcp`, then `tabs_create_mcp` and `navigate`). Take a
   screenshot. If GitHub shows a sign-in page, stop and ask the user to
   sign in; never type credentials.
2. **Fill the editor.** Locate it with `find` ("comment body textarea",
   "pull request title"). Set its text with `form_input`, then read the
   value back. If GitHub's editor dropped it, click into the textarea,
   select all, and use `computer` `type`. When editing an existing
   comment, change only what the user asked for and keep the rest of the
   text byte-for-byte.
3. **Switch Write to Preview.** Click the editor's **Preview** tab. Take
   a screenshot and check the rendering yourself first: broken tables,
   unclosed code fences, `#N` links pointing at the wrong repository (see
   `github-hygiene-pull-request-mirrors-commit` on `owner/repo#N`). Fix
   those in Write and come back to Preview before showing the user.
4. **Box the part to read.** Pass the text of `highlight-preview.js` to
   `javascript_tool`. It draws a red box around each editor showing its
   Preview, and the PR or issue title field when there is one, then
   scrolls the first into view. A result of `[]` means no Preview tab is
   selected, so go back to step 3.
5. **Bring the tab to the front**, so it is the first thing the user
   sees when the question appears:

   ```bash
   focus-chrome-tab.sh 'https://github.com/{owner}/{repo}/pull/{n}'
   ```

   Pass the tab's current URL, or a prefix of it, from `tabs_context_mcp`.
   It makes the tab its window's active tab, raises the window, and
   activates the browser. Claude in Chrome runs in whichever Chromium
   browser has the extension (Chrome, Brave, Edge, Chromium, Vivaldi), so
   the script searches every one that is running; `--app <name>` limits
   it. It prints the browser it focused, exits 1 when no tab matched, and
   is macOS only. Elsewhere, tell the user which window and tab to look at.
6. **Ask the user to check it**, in the same response as step 5 and
   immediately after it. `AskUserQuestion` blocks until the user
   answers, so the window has to be raised before the question rather
   than after it. Name the surface and the target by its canonical
   label, e.g. "Comment on jlesquembre/clj-nix#214 "Format Clojure and
   Nix files…" is drafted in Chrome, boxed in red, ready for you to
   send.", with these options:
   - **I'll send it**: the draft is ready as it is, or with the user's
     own edits in the browser.
   - **Change it**: the user says what to change; go back to step 2.
   - **Discard it**: go to step 8.
7. **Hand it over; the user sends it.** On an "I'll send it" answer,
   remove the boxes (`javascript_tool`: `clearDraftHighlight()`) and
   tell the user which button sends this surface: **Create pull
   request** or **Create draft pull request** for a new PR, **Create**
   for an issue, **Comment** for a comment, **Update comment** for an
   edit, **Reply** for a thread. Never click it, or any other button
   that sends, closes, approves or requests changes, and never press a
   key that submits the form. If the user says they sent it, take a
   screenshot to confirm the text landed and give them its URL.
8. **To discard a draft**, clear the textarea rather than just closing the
   tab, since GitHub keeps unsent comment text and restores it on the next
   visit. Use `javascript_tool` to set the value through the native setter,
   so GitHub's editor registers it, then read it back as empty:

   ```js
   const t = document.querySelector('textarea[placeholder="Add your comment here..."]');
   Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(t, "");
   t.dispatchEvent(new Event("input", { bubbles: true }));
   t.value.length;
   ```

9. **Leave the tab open** while the draft waits for the user to send
   it. Close the tab you opened only once the draft is sent or
   discarded, or when the user asks.

## Why this shape

- **Preview, not Write.** The user is checking how the text reads on
  GitHub: rendered tables, code blocks, links and mentions. The raw
  Markdown hides exactly the mistakes this check is for.
- **A red box.** A PR page has many text areas. The box tells the user
  which one is the draft without making them search for it.
- **Raise the window.** Claude in Chrome works in its own tab group, often
  in a window behind the terminal. A question about a draft the user
  cannot see gets answered without the draft being read.
- **The user sends.** Posting is public and outward-facing, so the user
  reads the draft where it lands and clicks the button themselves;
  `coding-agent-draft-in-browser` owns that rule.

## When to apply

- The agent is about to write GitHub text that people other than the
  user will read: a PR, PR description, issue, comment or review reply,
  whether or not the user asked for a draft or for the browser
  (`coding-agent-draft-in-browser` decides by the readers).
- The user wants to see GitHub's rendering before something is sent.
- Editing someone's existing comment or PR body, where seeing the result
  in place matters more than the raw diff of the text.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `chrome-browser`: loading the Claude in Chrome tools and working in a new tab of the user's browser.
- `coding-agent-browser-selection`: making sure the session drives the user's preferred browser and window before the first Claude in Chrome call.
- `coding-agent-draft-in-browser`: when text for other people is drafted in the browser, keeping personal details out of public drafts, and only the user sends.
- `github-hygiene-pull-request-mirrors-commit`: the default way to open a PR that mirrors a commit, and `owner/repo#N` references.
