# Dexterity V1 protocol decisions

- **Route:** fixed `constellation-v1`, version 1, with canonical points `(15,80) → (20,20) → (50,45) → (80,20) → (85,80)`.
- **Interaction:** right index finger, right hand, one completed practice trace followed by three completed scored traces. The target radius is 8 canonical route units.
- **Retry behavior:** early lift and cancellation end and preserve an attempt, then retry the same practice/scored round. Only the three completed scored sequences supply primary metrics.
- **Metric meanings:** `rmsError` is aggregate scored-sample RMSE; `rmsErrorMax` is maximum per-sequence RMSE; `swipeDist` is mean actual canonical path length per completed scored sequence.
- **Persistence:** a full raw session is encoded as one `RawCapture` JSON payload. The `DexterityResult.fingerLifts` attribute replaces `thumbLifts` through a Core Data renaming identifier.

These are MVP product/engineering decisions. They do not assert diagnostic accuracy, clinical validation, or severity cutoffs.
