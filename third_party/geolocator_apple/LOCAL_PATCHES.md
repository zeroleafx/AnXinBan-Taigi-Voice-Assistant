Based on geolocator_apple 2.4.3 (original LICENSE retained).

PermissionHandler uses the CLLocationManager instance authorizationStatus on
iOS 14+/macOS 11+ and retains the class method only for older systems.
Permission checks are dispatched to the main queue, where the manager and its
delegate are created/used; completion remains asynchronous.

Remove this override when the upstream package includes the equivalent fix.
