// SwooshDB — SpacetimeDB module for Swoosh v0.2 spike
//
// Tables: permission_state, scout_record, memory_candidate,
//         approved_memory, audit_event, setup_report
//
// Every state mutation goes through a reducer.
// Every reducer writes an audit event.

use spacetimedb::{reducer, table, ReducerContext, Table, Timestamp};

// ══════════════════════════════════════════════════════════════
// MARK: - Tables
// ══════════════════════════════════════════════════════════════

#[table(accessor = permission_state, public)]
#[derive(Clone)]
pub struct PermissionState {
    #[primary_key]
    pub permission: String,
    pub state: String,
    pub updated_at: Timestamp,
}

#[table(accessor = scout_record, public)]
#[derive(Clone)]
pub struct ScoutRecord {
    #[primary_key]
    pub id: String,
    pub source_id: String,
    pub kind: String,
    pub sensitivity: String,
    pub content: String,
    pub metadata_json: String,
    pub created_at: Timestamp,
}

#[table(accessor = memory_candidate, public)]
#[derive(Clone)]
pub struct MemoryCandidate {
    #[primary_key]
    pub id: String,
    pub text: String,
    pub category: String,
    pub confidence: f64,
    pub sensitivity: String,
    pub evidence_json: String,
    pub status: String, // pending | approved | rejected | edited
    pub created_at: Timestamp,
}

#[table(accessor = approved_memory, public)]
#[derive(Clone)]
pub struct ApprovedMemory {
    #[primary_key]
    pub id: String,
    pub text: String,
    pub category: String,
    pub sensitivity: String,
    pub source_candidate_id: String,
    pub approved_at: Timestamp,
}

#[table(accessor = audit_event, public)]
#[derive(Clone)]
pub struct AuditEvent {
    #[primary_key]
    pub id: String,
    pub event_type: String,
    pub subject_type: String,
    pub subject_id: String,
    pub metadata_json: String,
    pub created_at: Timestamp,
}

#[table(accessor = setup_report, public)]
#[derive(Clone)]
pub struct SetupReport {
    #[primary_key]
    pub id: String,
    pub markdown: String,
    pub created_at: Timestamp,
}

// ══════════════════════════════════════════════════════════════
// MARK: - Helpers
// ══════════════════════════════════════════════════════════════

use std::sync::atomic::{AtomicU64, Ordering};

static ID_COUNTER: AtomicU64 = AtomicU64::new(0);

fn new_id() -> String {
    let count = ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("swoosh-{:016x}", count)
}

fn audit(ctx: &ReducerContext, event_type: &str, subject_type: &str, subject_id: &str, meta: &str) {
    ctx.db.audit_event().insert(AuditEvent {
        id: new_id(),
        event_type: event_type.to_string(),
        subject_type: subject_type.to_string(),
        subject_id: subject_id.to_string(),
        metadata_json: meta.to_string(),
        created_at: ctx.timestamp,
    });
}

// ══════════════════════════════════════════════════════════════
// MARK: - Permission reducers
// ══════════════════════════════════════════════════════════════

#[reducer]
pub fn set_permission(ctx: &ReducerContext, permission: String, state: String) {
    // Delete existing if present
    if let Some(existing) = ctx.db.permission_state().permission().find(&permission) {
        ctx.db.permission_state().permission().delete(&existing.permission);
    }
    ctx.db.permission_state().insert(PermissionState {
        permission: permission.clone(),
        state: state.clone(),
        updated_at: ctx.timestamp,
    });
    audit(ctx, "permission.set", "permission", &permission,
        &format!(r#"{{"state":"{}"}}"#, state));
}

// ══════════════════════════════════════════════════════════════
// MARK: - Scout reducers
// ══════════════════════════════════════════════════════════════

#[reducer]
pub fn submit_scout_record(
    ctx: &ReducerContext,
    id: String,
    source_id: String,
    kind: String,
    sensitivity: String,
    content: String,
    metadata_json: String,
) {
    ctx.db.scout_record().insert(ScoutRecord {
        id: id.clone(),
        source_id,
        kind,
        sensitivity,
        content,
        metadata_json,
        created_at: ctx.timestamp,
    });
    audit(ctx, "scout.record_submitted", "scout_record", &id, "{}");
}

// ══════════════════════════════════════════════════════════════
// MARK: - Memory candidate reducers
// ══════════════════════════════════════════════════════════════

#[reducer]
pub fn create_memory_candidate(
    ctx: &ReducerContext,
    id: String,
    text: String,
    category: String,
    confidence: f64,
    sensitivity: String,
    evidence_json: String,
) {
    ctx.db.memory_candidate().insert(MemoryCandidate {
        id: id.clone(),
        text,
        category,
        confidence,
        sensitivity,
        evidence_json,
        status: "pending".to_string(),
        created_at: ctx.timestamp,
    });
    audit(ctx, "memory.candidate_created", "memory_candidate", &id, "{}");
}

#[reducer]
pub fn approve_memory_candidate(
    ctx: &ReducerContext,
    candidate_id: String,
    final_text: String,
) {
    let candidate = match ctx.db.memory_candidate().id().find(&candidate_id) {
        Some(c) => c,
        None => {
            log::error!("memory candidate not found: {}", candidate_id);
            return;
        }
    };

    if candidate.status != "pending" && candidate.status != "edited" {
        log::error!("candidate {} is not approvable (status: {})", candidate_id, candidate.status);
        return;
    }

    // Delete old, insert updated status
    ctx.db.memory_candidate().id().delete(&candidate_id);
    ctx.db.memory_candidate().insert(MemoryCandidate {
        status: "approved".to_string(),
        ..candidate.clone()
    });

    // Create approved memory
    let memory_id = new_id();
    ctx.db.approved_memory().insert(ApprovedMemory {
        id: memory_id.clone(),
        text: final_text,
        category: candidate.category,
        sensitivity: candidate.sensitivity,
        source_candidate_id: candidate_id.clone(),
        approved_at: ctx.timestamp,
    });

    audit(ctx, "memory.candidate_approved", "memory_candidate", &candidate_id,
        &format!(r#"{{"approved_memory_id":"{}"}}"#, memory_id));
}

#[reducer]
pub fn reject_memory_candidate(
    ctx: &ReducerContext,
    candidate_id: String,
    reason: String,
) {
    let candidate = match ctx.db.memory_candidate().id().find(&candidate_id) {
        Some(c) => c,
        None => {
            log::error!("memory candidate not found: {}", candidate_id);
            return;
        }
    };

    if candidate.status != "pending" && candidate.status != "edited" {
        log::error!("candidate {} is not rejectable (status: {})", candidate_id, candidate.status);
        return;
    }

    ctx.db.memory_candidate().id().delete(&candidate_id);
    ctx.db.memory_candidate().insert(MemoryCandidate {
        status: "rejected".to_string(),
        ..candidate
    });

    audit(ctx, "memory.candidate_rejected", "memory_candidate", &candidate_id,
        &format!(r#"{{"reason":"{}"}}"#, reason));
}

// ══════════════════════════════════════════════════════════════
// MARK: - Setup report reducer
// ══════════════════════════════════════════════════════════════

#[reducer]
pub fn save_setup_report(ctx: &ReducerContext, markdown: String) {
    let id = new_id();
    ctx.db.setup_report().insert(SetupReport {
        id: id.clone(),
        markdown,
        created_at: ctx.timestamp,
    });
    audit(ctx, "setup.report_saved", "setup_report", &id, "{}");
}
