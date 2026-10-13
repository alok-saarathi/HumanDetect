# 15 · Hybrid tiered pipeline (target architecture)

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Idea:** combine the winners.
- **On the phone:** cheap checks give instant "retake" feedback.
- **On the server:** authoritative checks give the final verdict, because anything client-side can be bypassed in a modified app.

```
Phone:   03 capture controls ─► 01 face present (count/size/pose) ─► [05 blink] ─► [02/12/14 on-device] ─► upload
Server:  03 metadata + nonce check ─► 12/14 classifier ─► 04 forensics ─► 07 dedup ─► accept / reject + reason
```

**Rollout:** shadow mode first (log decisions without blocking, and compare with ops review), then enforce.
