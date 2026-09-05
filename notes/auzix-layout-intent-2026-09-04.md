# AUZiX layout intent — operator clarification

AUZiX reorganizes Linux into an understandable workspace, drawing inspiration
from Amiga, GoboLinux and Nix. It uses APK; it is not Alpine. The aim is to
reduce inherited Unix layout complexity, not reinvent working applications.

- `/Programs/<Name>` is the center of an application: its commands, resources,
  related directories and any dedicated libraries. Keep the structure beneath
  it as simple as practical.
- `/Libraries` provides shared libraries where appropriate. Launchers load the
  library and command paths their workload needs, rather than placing every
  installed library on a global boot-time search path.
- `/Services/<Name>` is the center of a service: working configuration, related
  files and directories, and eventually its container outputs. Existing
  service commands and config paths are authoritative when validating it.
- Compatibility views enable software to work with this layout. They should
  not displace the user-facing application/service organization.

The longer-term service model is a living workspace and cluster: scheduling a
workload on a suitable host while connecting its output back to the workspace
or network. Services needing direct kernel access may run natively and should
follow a similar organizational model. This is future direction, not an alpha
release prerequisite.

For the current alpha: adapt known-good application arguments, library scope,
package activation and service startup to AUZiX paths. Package those effects,
reproduce them through the image builder, and verify actual launches. Avoid
global environment expansion as a substitute for correct package ownership.
