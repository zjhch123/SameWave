# One-on-One Live Meeting Translation — Conversation Rendering Requirements and State Machine

> Audience: developers
> Goal: define conversation Section segmentation, sealing, and translation rendering for one-on-one live translation.
> Type: product design baseline, not a direct description of current runtime behavior.
> Implementation comparison: [Live captions and translation](02-live-captions-and-translation.md), [`CaptionStore.swift`](../Sources/Meeting/CaptionStore.swift), and [`CaptureCoordinator.swift`](../Sources/Meeting/CaptureCoordinator.swift).

---

## 1. Core concepts

- **Section:** continuous speech by one person, uninterrupted by the other. Each Section belongs to one speaker and contains source and target text; translation may arrive asynchronously.
- **Speaker symmetry:** ownership depends only on who speaks, with no special treatment for me versus the other participant. The first speaker owns Section 0.
- **Sealing:** stop appending new ASR source text, but **allow corrections to existing source text** and asynchronous translation completion.
- **Orthogonal rules:** segmentation (Rule A) and translation (Rule B) are independent. Translation state never decides segmentation.

---

## 2. Two core rules

**Rule A — Segmentation**

When speech switches from the current Section's owner to the other person, immediately seal the current Section and open one for the new speaker. If the interrupted speaker continues, that continuation is also a **new Section**.

**Rule B — Independent translation**

Sealing stops only new source appends. Translation continues independently until complete. **Translation state never participates in segmentation decisions**; it only determines whether the UI shows Translating.

> All scenarios follow from these two rules.

---

## 3. Derived scenarios

Assume the other participant speaks first; the reverse is symmetric.

Initial state: the other participant speaks → Section 0 (other).

When I start speaking:

| Case | Other participant's state | Result |
|---|---|---|
| 3.1 | Still speaking; interrupted | Seal Section 0, translation continues; open Section 1 for me; their continuation opens Section 2 |
| 3.2 | Finished speaking; translation still finishing | Seal Section 0, translation continues; open Section 1 for me |
| 3.3 | Speech and translation both complete | Open Section 1 for me |

> Cases 3.2 and 3.3 have identical segmentation; only 3.2 still shows Translating on Section 0.

---

## 4. Confirmed boundary rules

1. **Speaker symmetry:** the first speaker owns Section 0 regardless of identity.
2. **Symmetric interruption:** the same rules apply in either direction.
3. **Overlap order:** insert the interrupter's Section first, then the interrupted speaker's continuation. In 3.1, Section 1 (me) precedes Section 2 (other continuing).
4. **Interrupted-sentence context:** reuse the existing sliding window when interruption splits a sentence, preserving cross-Section meaning rather than translating fragments independently.
5. **Short acknowledgments/fillers** such as “mm-hm,” “OK,” or “yeah” use exactly the same triggers as ordinary speech, including sealing and new Sections. Prefer simple logic without exceptions.
6. **ASR revisions:** permit corrections after sealing; prohibit only new content appends.

---

## 5. State definitions

### 5.1 Section lifecycle

```text
ACTIVE      Receiving this speaker's ASR source; appends and corrections allowed
SEALED      No new source appends; existing source may be corrected; translation pending/active
TRANSLATING Translation is being generated asynchronously; may coexist with SEALED
DONE        Source frozen and translation complete; terminal state
```

`SEALED` and `TRANSLATING` are orthogonal dimensions. Prefer two fields:

- `contentState`: `OPEN | SEALED` — whether new source is accepted.
- `translationState`: `PENDING | TRANSLATING | DONE`.

Unless ambiguous, “state” below refers to `contentState`.

### 5.2 Section structure

```text
Section {
  id               : int          // Global increasing ID; display-order basis
  speaker          : SpeakerId    // Symmetric identity; ownership only
  contentState     : OPEN | SEALED
  translationState : PENDING | TRANSLATING | DONE
  sourceText       : string       // OPEN: append/correct; SEALED: correct only
  targetText       : string       // Asynchronous translation appends
  startTime        : timestamp    // Overlap ordering
}
```

### 5.3 Global controller state

```text
IDLE          Nobody speaking
SINGLE        One speaker ACTIVE
OVERLAP       Both speakers active; interruption in progress
```

---

## 6. Section transitions

```text
        ┌──────── Append/correct source ────────┐
        ▼                                       │
   [ CREATE ] ──► ACTIVE(OPEN) ──────────────────┘
                     │
                     │ Seal: other speaker starts
                     ▼
                  SEALED ─── Correct source ────┐
                     │  ▲                       │
                     │  └───────────────────────┘
                     │
 Translation work ───┼──────────────────────────►
                     ▼
   PENDING ──► TRANSLATING ──► DONE
                     ▲   │
                     └───┘ Append translated chunks

 Terminal condition: contentState == SEALED && translationState == DONE ⇒ DONE
```

Sealing and translation are decoupled. Sealing is `ACTIVE → SEALED`; translation advances independently through `PENDING/TRANSLATING/DONE` without blocking segmentation.

---

## 7. Controller transitions

| Current | Event | Next | Meaning |
|---|---|---|---|
| IDLE | onSpeechStart(A) | SINGLE | Create Section(A) |
| SINGLE | onSpeechStart(B), B differs from current speaker | OVERLAP | Seal A; create Section(B) |
| SINGLE | onSpeechEnd(A) | IDLE | Seal A |
| SINGLE | onSpeechStart(A), same speaker; theoretically absent | SINGLE | Ignore/merge |
| OVERLAP | onSpeechEnd(one speaker) | SINGLE | Other remains active |
| OVERLAP | onSpeechEnd(both in succession) | IDLE | Seal all |
| OVERLAP | onSpeechStart(interrupted speaker continuing) | OVERLAP | Create a continuation Section |

---

## 8. Events and actions

| Event | Condition | Action |
|---|---|---|
| `onSpeechStart(spk)` | No current ACTIVE Section | Create Section(spk) → ACTIVE; controller → SINGLE |
| `onSpeechStart(spk)` | Another speaker has an ACTIVE Section | Seal it (`OPEN→SEALED`); create Section(spk) → ACTIVE; controller → OVERLAP |
| `onAsrUpdate(spk, text)` | Speaker's Section OPEN | Append/correct sourceText |
| `onAsrUpdate(spk, text)` | Speaker's Section SEALED | **Correct existing sourceText only**; reject additions |
| `onSpeechEnd(spk)` | Any | Mark speaker inactive; controller → IDLE if none active, otherwise SINGLE |
| `onTranslationChunk(id, t)` | Any | Append targetText; translationState → TRANSLATING |
| `onTranslationDone(id)` | Any | translationState → DONE; Section DONE if contentState==SEALED |

> Short acknowledgments have no special handling: `onSpeechStart` treats “mm-hm/OK/yeah” like any other speech and triggers sealing.

---

## 9. Interruption walkthrough (case 3.1)

```text
t0  Other participant speaks → Section 0 (other, ACTIVE)
t1  I interrupt
      · Section 0: OPEN → SEALED; translation continues
      · Create Section 1 (me, ACTIVE)
      · Controller → OVERLAP
t2  Other participant continues
      · Create Section 2 (other, ACTIVE)
t3  I finish: onSpeechEnd(me)
      · Section 1 → SEALED
      · Controller → SINGLE; other participant remains active
```

Display strictly by ascending `section.id`. Creating the interrupter first and the continuation second naturally satisfies boundary rule 3: Section 1 before Section 2.

---

## 10. Segmentation pseudocode

```python
def on_speech_start(spk):
    cur = active_section_of_other_speaker(spk)
    if cur is not None:
        seal(cur)                     # OPEN -> SEALED; schedule translation
    new_sec = create_section(spk)     # Increasing ID, ACTIVE/OPEN
    new_sec.startTime = now()
    update_controller_state()

def on_asr_update(spk, text):
    sec = active_section_of(spk)
    if sec.contentState == OPEN:
        sec.sourceText = merge_append_or_correct(sec.sourceText, text)
    else:  # SEALED
        sec.sourceText = correct_only(sec.sourceText, text)  # Reject new content
    reschedule_translation(sec)

def seal(sec):
    sec.contentState = SEALED
    schedule_translation(sec)         # Enter PENDING

def on_translation_chunk(id, chunk):
    sec = get(id)
    sec.targetText += chunk
    sec.translationState = TRANSLATING

def on_translation_done(id):
    sec = get(id)
    sec.translationState = DONE
    # Terminal state derives from contentState==SEALED && translationState==DONE
```

---

## 11. Translation context: sliding window

When interruption splits a sentence across Sections, such as the tail of Section 0 and head of Section 2, translation must not treat each independently. Reuse the existing sliding window: include neighboring prior context from the same speaker when translating a Section to preserve meaning across boundaries.

```python
def translate(sec):
    context = sliding_window(sec.speaker, before=sec)  # Reuse existing mechanism
    submit(source=sec.sourceText, context=context)
```

---

## 12. Open engineering question

- **Concurrent translation across Sections:** repeated interruptions can leave multiple SEALED Sections with `translationState != DONE`, such as Sections 0 and 2. Developers should choose scheduling, queues, and performance strategies: serial execution, parallel work with frozen context, priorities, or another justified approach.
