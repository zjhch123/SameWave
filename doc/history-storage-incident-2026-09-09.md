# History Storage Incident: September 9, 2026

## Root cause

SameWave used SwiftData's default persistent store while running without App Sandbox. In this environment, that default is `~/Library/Application Support/default.store`, independent of the executable's bundle identifier. It is a shared filesystem location, not a directory owned by SameWave.

Another process, `icloudmailagent`, opened that same database with a different model. Core Data's automatic lightweight migration removed the six SameWave entities. When SameWave later reopened the file, its own automatic migration recreated empty tables. No exception was required for either migration, so the application treated the resulting empty library as a successful open.

The root defect was application storage ownership: an unsandboxed app relied on an unscoped framework default. Automatic schema replacement amplified the collision into data loss, and the lack of a model check allowed the next launch to conceal the foreign schema behind an apparently valid empty store.

## What the default store means

There is no system-wide database service intended to combine application data here. `default.store` is an ordinary local SQLite file chosen by the framework when no explicit persistent configuration is provided. In this unsandboxed environment, two applications choosing that default can address the same physical file. A SwiftData `ModelContainer` owns an application's model and contexts; constructing one does not itself establish a per-application filesystem directory or an App Sandbox boundary.

SameWave's old initializer accepted a missing configuration and passed an empty configuration array to `ModelContainer`. `project.yml` explicitly disables App Sandbox. The code therefore defined SameWave's tables but failed to choose a file location dedicated to SameWave. Having a distinct bundle identifier did not fix that omission, as the native two-process reproduction confirms.

The corrected database is stored outside the replaceable `SameWave.app` bundle at `~/Library/Application Support/SameWave/MeetingHistory.store`. This is the application's dedicated data file. A normal application installation replaces the executable bundle, not this data directory. Runtime open-file inspection confirms that the installed process uses this path and has no open handle to the old `default.store`.

Dedicated filenames prevent the reproduced accidental collision. SameWave remains unsandboxed; the path is not an OS-enforced boundary against other processes running as the same user. The incident evidence establishes schema replacement, not upload of meeting content to iCloud.

## Evidence and timeline

All times below are Asia/Shanghai on September 9, 2026.

| Time | Evidence | Meaning |
|---|---|---|
| 10:27:54.944 | Preserved store transaction `4066` identifies bundle `com.apple.icloudmailagent`, process `icloudmailagent`, and the Core Data schema migrator as author. | Another process migrated this exact store before the afternoon development task. |
| 10:27:54.995 | The system log from `icloudmailagent` says persistent history must be truncated because `TranscriptLine`, `MeetingRecord`, `MeetingVocabularyTerm`, `InsightDefinition`, `MeetingDocument`, and `InsightSnapshot` are being removed. | The schema replacement removed every application data model. |
| Before 17:19 | The already-running desktop application still displayed its previously loaded meetings. | A populated UI did not establish that the underlying persistent store remained intact. |
| 17:19:06.991 | Store transaction `4067` identifies `com.plus.samewave`, process `SameWave`, and another schema migration. | Restarting reopened the changed store and recreated the SameWave schema. |
| After restart | All six application tables were empty; the store UUID was unchanged and many pages remained on the freelist. | This was destructive reuse of the existing file, not selection of a different fresh database. |

The preserved transaction timestamps use the Core Data epoch, January 1, 2001 UTC. The process identities come from the transaction's references into `ATRANSACTIONSTRING`. The unified log independently corroborates the database evidence.

`icloudmailagent` is an Apple iCloud Mail background executable, separate from SameWave. The incident's structured unified log identifies its executable as `/usr/libexec/icloudmailagent`; this is not merely an inference from a database label. Its private internal trigger for opening the default path remains outside the evidence available to this investigation.

The default-store call was already present when history was introduced in commit `f22498e`; `9c356b1` made configuration injectable but retained the default production path. The Vocabulary UI change did not modify the persistence model. Hosted tests used memory or explicit temporary stores, and the destructive transaction predates those test runs. Normal meeting deletion also does not explain the schema-migrator author or removal of all entity tables.

We do not infer which private API or internal event caused `icloudmailagent` to choose this path. Its write to the shared file and removal of the application entities are directly evidenced. SameWave must own its storage path regardless of another process's implementation.

## Native reproduction

A standalone probe used the actual six SameWave model types and the pre-fix `ModelContainer(for: schema, configurations: [])` call. Two separately launched application bundles had different identifiers, `com.example.samewave-history-probe` and `com.example.foreign-storage-probe`. Both were given the same temporary home using `CFFIXED_USER_HOME`. The probe refused to open a store unless its resolved path was under its isolated temporary directory.

1. Both bundles reported the identical `Library/Application Support/default.store` URL.
2. The history process saved one synthetic meeting and exited.
3. The foreign process opened its own single-entity SwiftData model using the default configuration, then saved a synthetic row.
4. Core Data emitted the same six-entity removal message as the incident log.
5. The history process reopened with the old construction call and returned zero meetings, without throwing a storage error.
6. Repeating the sequence with `MeetingHistoryStore.persistentConfiguration()` retained the synthetic meeting at the new explicit path while the foreign process continued using `default.store`.

| Configuration | Before foreign process | After foreign process and history reopen |
|---|---:|---:|
| Old framework default | 1 meeting | 0 meetings |
| Explicit SameWave path | 1 meeting | 1 meeting |

This establishes the failure mechanism independently of the damaged personal database. No actual mail process or user database was used in the reproduction.

## Corrections and invariants

The production path is now `~/Library/Application Support/SameWave/MeetingHistory.store`. Every history container requires an explicit configuration. App assembly selects the application-owned configuration; tests select memory or a temporary file.

Before creating a persistent `ModelContainer` for an existing file, SameWave reads its Core Data metadata with `NSReadOnlyPersistentStoreOption`. The stored entity-name set must exactly match the six models in the current schema. A different or missing set fails before automatic migration can replace entities. A corrupt or unreadable file propagates the native error. Neither failure creates a replacement store, switches to memory, or imports an older backup.

| Store condition | Required behavior |
|---|---|
| New application-owned path | Create the directory and current store. |
| Existing store with the expected entity set | Open and preserve meetings and relationships. |
| Existing foreign or incomplete entity set | Report a localized storage failure; preserve the database and WAL. |
| Existing unreadable database or blocked directory | Report the actual failure; preserve existing bytes. |
| In-memory test configuration | Perform no persistent-file preflight. |

The entity check establishes model ownership; it is not a parallel persistence implementation or a compatibility layer. The explicit path addresses accidental default-path reuse. Neither mechanism is an OS-level barrier against a process deliberately modifying an accessible file.

## Regression coverage

`MeetingHistoryStoreTests` now performs a real automatic migration of a temporary shared store to a foreign SwiftData model, then verifies that the application-owned meeting and transcript survive reopening. It also verifies that reopening the foreign store through SameWave is rejected.

Another test places a foreign model directly at the configured history path. The failed SameWave open leaves the database and WAL byte-identical, retains the foreign model metadata, and preserves the foreign row. Corrupt-file and blocked-directory cases verify preservation and error propagation. Existing on-disk workspace tests continue covering attachments, vocabulary, definitions, and insight payloads across reopen. Localization tests cover the new preservation message in English and Simplified Chinese.

Run the production validation gate and relevant regressions with the `SameWave` scheme and destination `platform=macOS,arch=arm64`. The standalone two-process transcript is retained with local incident evidence; personal recovery files and content are excluded from the repository.

## Recovery and prevention are separate

Incident recovery used preserved database pages, an intact earlier backup, and surviving metadata on isolated copies. Restoring content did not fix the collision. The explicit path and preflight check are permanent production changes, with executable regression coverage for the destructive mechanism. No old shared-store access or automatic recovery branch remains in application code.

See [Session lifecycle and data](03-session-lifecycle-and-data.md) for the runtime contract and [Development and validation](06-development-and-validation.md) for validation guidance.
