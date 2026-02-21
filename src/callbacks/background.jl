# ─── Background Callback Manager ─────────────────────────────────────────────
# Phase 3 implementation — placeholder for now.

"""
    AbstractBackgroundManager

Abstract type for background callback managers.
Subtype this to implement custom background task execution.
"""
abstract type AbstractBackgroundManager end

"""
    ThreadPoolManager <: AbstractBackgroundManager

Default background callback manager using Julia's built-in threading.
Uses `Threads.@spawn` for task execution.
"""
struct ThreadPoolManager <: AbstractBackgroundManager end
