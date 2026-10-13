# Project scripts

No scripts are supplied or required. Add a script only when it simplifies a real, repeated project task such as building, testing, or running a local tool.

Prefer existing toolchain commands over wrappers that add no value. Keep scripts small and focused, avoid unnecessary dependencies, and document each script's purpose, exact invocation, prerequisites, and side effects here. Fail clearly when prerequisites are missing. Do not embed credentials.

Once scripts exist, link their useful commands from the project README. Do not add automation, CI/CD, or a release pipeline solely because this directory exists.
