# Property capture

A variation of the human final-capture path. The technique stays: a small check on the phone, then the same check on the server, and the server result is the decision. The question changes from "is a person visible?" to "is this the property photo we asked for?"

Property means a home, a shop, or another premises. Each upload belongs to a named slot. The app already knows which slot is open.

## Slots

Start with these. Split shop floor and shop shutter later if a single shop photo is too vague.

| Slot | What the photo should show |
|---|---|
| Interior | Inside a home or shop: a room, hall, or shop floor |
| Exterior front | The street side: entrance, main door or shutter, house number or name board, street or lane |
| Exterior back | The rear: back wall, yard or service side, main entrance not the subject |

Front and back are both "a building outside." Write them as visible contents, not as a compass direction. A generic model does not know which side of this property it is seeing.

## How the check works

CLIP scores a picture against sentences. The TinyCLIP image encoder already on the phone can stay. The face prompts cannot. Those sentences are about people, screens, and cartoons.

The model is not asked an open question. It picks among a fixed list, and the photo passes only when the expected slot wins.

Two thresholds:

- The expected slot is the top score.
- It beats the second-place slot by a margin. With several slots, a raw probability of 0.5 is a hard bar, because the score is split. A photo that is 0.34 interior and 0.33 exterior fails even though interior is slightly ahead.

Keep a reject list beside the slots, each with its own threshold:

- a document, floor plan, or map
- a screenshot of a listing or of Maps
- a close-up of a person
- a random object, or a landscape with no building

Those are pictures, just not the property view that was asked for.

## Phone and server

1. The app opens a named slot.
2. The phone scores TinyCLIP against that slot, the other slots, and the reject list. A miss stops the upload.
3. The server runs the same sentences on a stronger CLIP. SigLIP 2 was the accurate server candidate in the zero-shot plan. Its margin is the decision.
4. Inside one application, reject a photo that matches another slot's file.
5. For exterior front and back only, also require a GPS fix near the property and a heading that matches that side.

SmolVLM is the later judge for a compound sentence CLIP handles badly, such as "rear wall of a house, yard visible, main door not the subject." Room-type classifiers trained on field photos come after this, once there are labeled examples. The prompt list does not need those examples.

## Checks that matter here

The human path correctly dropped these. Property capture needs them.

- **Same file in two slots.** Uploading the front photo again as the back photo is the failure. Compare photos inside one application with the perceptual hash already built for duplicates. The same JPEG, or a near copy, cannot fill two slots. This is not a global "no duplicates ever" rule.
- **A downloaded listing.** A photo of a screen was acceptable for a person. For a property it is often someone else's listing or a Maps screenshot. A "screenshot / photo of a monitor" prompt, and the blur, glare, and moiré rules, belong here as a reject.
- **Required objects, not only a scene label.** An open-vocabulary detector, the same family as the OWLv2 experiment, can demand a door or shutter for a front, a stove or counter for a kitchen, a signboard for a shop. A scene label says "interior." An object check says the entrance was actually photographed.
- **The set, not one photo.** The application passes when every required slot has passed its own question. One good interior does not cover a missing back.
- **Usable, not just on-topic.** A dark frame, a finger over the lens, or a wall so close that no room is visible can still score as an interior. A sharpness and brightness floor keeps an unusable photo from passing.

GPS near the property coordinate, and the compass heading while the photo is taken, are the signals that separate front from back. A front photo should face the street. A back photo should face away from it. CLIP cannot see that. Street View or satellite matching against the claimed address is a later check: it is heavy, and the imagery is often missing or stale.
