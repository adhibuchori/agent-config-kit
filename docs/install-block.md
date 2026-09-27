1. **Add the marketplace** (once per machine). In a terminal:

   ```bash
   claude plugin marketplace add adhibuchori/agent-config-kit
   ```

   Inside Claude Code, `/plugin marketplace add adhibuchori/agent-config-kit` does the same.

2. **Install agent-core and one stack plugin.** Inside Claude Code:

   ```text
   /plugin install agent-core@agent-config-kit
   /plugin install agent-fe-nextjs@agent-config-kit
   ```

   Swap `agent-fe-nextjs` for the stack plugin that fits your repo. Installing a stack plugin also
   installs agent-core, because every stack plugin depends on it. If the new commands do not show
   up, restart Claude Code.

3. **Run setup in your repo**, for the stack plugin you installed:

   ```text
   /agent-fe-nextjs:setup
   ```

   Setup asks a few questions, one at a time, each with a recommended answer. Then it shows a dry
   run of every file it would write, and writes only when you reply **go**. Commit the new files
   together with `.claude/agent-config-kit.lock`: the lock is what turns the hooks on for everyone
   who clones the repo.

**Updates** reach you only when a plugin's version is bumped. Run
`claude plugin marketplace update agent-config-kit`, then
`claude plugin update <plugin>@agent-config-kit`, restart Claude Code, and run `/<plugin>:sync` in
each repo.
