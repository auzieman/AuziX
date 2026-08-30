# AUZiX package-factory working prompt

Work from declared package fragments and contracts. Before changing code,
classify the primary failure domain as source, transform, package, transaction,
activation, media, or deployment. Modify only the owning layer. Do not repair
one layer by injecting files owned by another.

At the start of a package task:

1. read `packaging/operator-contract.json`;
2. read the selected profile, package definition and referenced fragments;
3. inspect the latest lock and receipts when they exist;
4. state the invariant, allowed paths, forbidden paths and required gates;
5. compare with the last proven artifact at the same boundary;
6. make the smallest bounded change;
7. run schema, package and executable gates before promotion;
8. stop at the declared promotion boundary.

The package factory owns package intent and payload transformation. apk-tools
owns dependency transactions and installed state. Activation owns generated
system surfaces. Media code owns only the media envelope.

On `feature/apk-package-core-20260829`, compatibility with attic orchestration
is not a design requirement. Preserve proven payload knowledge and behavioral
gates; do not preserve a legacy controller merely because it existed first.
