---
name: github-workflow-browser-draft-preview
description: |
  Draft GitHub text in the user's own browser with Claude in Chrome — a
  new pull request, an issue or PR comment, a review reply, or an edit
  to an existing PR body or comment — and leave it unsubmitted for the
  user to check. After filling the editor, switch it from Write to
  Preview, draw a red box around the rendered draft
  (`highlight-preview.js`), bring that browser tab and window to the front
  (`focus-chrome-tab.sh`), and ask the user to check it before anything
  is submitted. Use when the user asks to draft, write up or edit a PR,
  comment or reply "in the browser" or "in Chrome", or wants to see the
  rendered GitHub Markdown before it posts.
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

# github-workflow-browser-draft-preview

Write the draft where it will be posted, show it rendered, and put it in
front of the user. The user reads GitHub's own Preview, in their own
signed-in browser, with the part to read boxed in red, and nothing posts
until they say so.

## How to load this skill

Load it before the first Claude in Chrome call of a GitHub drafting task.
Load the `claude-in-chrome` skill too: it covers loading the browser
tools in one `ToolSearch` call and working in a new tab. This skill only
drafts; it never clicks a submit button without the user's answer from
step 6.

For a PR that should mirror a commit (`github-hygiene-pull-request-mirrors-commit`),
that skill's script is the default. Use this one when the user wants to
see or adjust the rendered text before it posts.

## Where the bundled scripts install

Both scripts sit in a `scripts/` directory alongside this `SKILL.md`:

- **User scope:** `~/.claude/skills/github-workflow-browser-draft-preview/scripts/`
- **Project scope:** `<project-root>/.claude/skills/github-workflow-browser-draft-preview/scripts/`

`focus-chrome-tab.sh` is run with Bash. `highlight-preview.js` is not
run directly: Read it and pass its text to `javascript_tool`.

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
   than after it. Name the surface and the target, e.g. "Comment on
   jlesquembre/clj-nix#214 is drafted in Chrome, boxed in red. Post it?",
   with these options:
   - **Post it**: submit exactly what is in the editor now.
   - **I edited it in the browser, post that**: read the editor's
     current value back, show it in chat, then submit.
   - **Change it**: the user says what to change; go back to step 2.
   - **Leave it unposted**: keep the tab open and the draft unsent.
7. **Submit only on a Post answer.** Remove the boxes first
   (`javascript_tool`: `clearDraftHighlight()`), then click the one
   button that posts this surface: **Create pull request** or **Create
   draft pull request**, as the user chose, for a new PR; **Comment** for
   a comment; **Update comment** for an edit; **Reply** for a thread.
   Never **Close with comment**, **Approve** or **Request changes**
   unless the user asked for exactly that. Take a screenshot, confirm
   the text posted, and give the user its URL.
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

9. **Close the tab** you opened, unless the user chose to leave the draft
   unposted or asked to keep the tab.

## Why this shape

- **Preview, not Write.** The user is checking how the text reads on
  GitHub: rendered tables, code blocks, links and mentions. The raw
  Markdown hides exactly the mistakes this check is for.
- **A red box.** A PR page has many text areas. The box tells the user
  which one is the draft without making them search for it.
- **Raise the window.** Claude in Chrome works in its own tab group, often
  in a window behind the terminal. A question about a draft the user
  cannot see gets answered without the draft being read.
- **Ask, then click.** Posting is public and outward-facing. The user's
  answer to the question is the permission for that one post; it does not
  carry over to the next draft.

## When to apply

- The user asks to draft, write or edit a PR, PR description, comment,
  reply or issue in the browser or in Chrome.
- The user wants to see GitHub's rendering before something posts.
- Editing someone's existing comment or PR body, where seeing the result
  in place matters more than the raw diff of the text.
