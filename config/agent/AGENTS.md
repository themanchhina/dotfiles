# global agent instructions

- Weigh technical decisions on quality, simplicity, robustness, scalability and long-term maintainability - not on how much work they are.
- Match the surrounding code unless there is a better way - say what you're deviating to and why, before you write it.
- Keep the main thread for conclusions - breadth goes to a subagent whose findings come back with quotes and paths to re-check.
- Pipe heavy output to a file you cite, unless I asked to see it.
- Choose the form by what the information is - tables for comparisons, a diagram for flows and how pieces fit, structured text otherwise. Output for agents can be dense.
- Never add yourself as a commit co-author.
- Use Jev (TypeSafe System One / `jev` CLI) for semantic decisions, routing, scoring, and classification — prefer typed judgments over LLM text-generation loops or brittle heuristics.

# maintaining this file

- Only short instructions that all sessions require. Propose edits accordingly.
- All edits to this file, and any new instructions file, wait for my review.
