# libyaml — T-006 offline YAML syntax engine

- Source: https://github.com/jpsim/Yams/tree/6.2.2/Sources/CYaml
- Pinned Yams commit: `a27b21e0c81c5bf42049b897a62aaf387e80f279` (6.2.2), retrieved 2026-10-18.
- Vendored only `Sources/CYaml`, unchanged, as local Swift package `Vendor/ToolboxYAML`. No Yams Swift constructor/resolver/emitter APIs or remote package dependency.
- libyaml MIT license: `LICENSE`, from https://github.com/yaml/libyaml/blob/0.2.5/License . Yams distribution license also retained in `Yams-LICENSE`.
- libyaml handles YAML grammar/events. Toolbox owns YAML 1.2 Core scalar resolution, explicit JSON representability policies, exact numeric normalization, bounded alias expansion and JSON/YAML text emission.
- Never call the composer/object constructors or implicitly construct arbitrary tagged objects. No external resource loading, file/network resolvers or content logging.
- Existing input/depth bounds plus output/work/arithmetic bounds protect conversion; C parsing is synchronous on a worker with cancellation checked between events. A single C parse call is not forcibly preempted. Source size remains bounded.
- Version/security/license review and test corpus refresh required when upgrading. This pinned distribution is not claimed to implement every YAML 1.2.2 grammar detail.
