-- Email pipeline tables for the Resend integration.
-- These tables are consumed by the send-email / approve-email / resend-inbound-webhook
-- edge functions but were never present in the migration history (created out-of-band
-- in the original project). Defined idempotently so this can run on a fresh DB.

-- ── Pending email approvals ────────────────────────────────────────────────
-- send-email holds outbound mail here when its type requires approval; approve-email
-- reads the row, sends via Resend, and flips status.
CREATE TABLE IF NOT EXISTS pending_email_approvals (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email_type     text NOT NULL,
  to_addresses   text[] NOT NULL,
  from_address   text,
  reply_to       text,
  cc             text[],
  bcc            text[],
  subject        text,
  html           text,
  text_content   text,
  status         text NOT NULL DEFAULT 'pending',
  approval_token text NOT NULL UNIQUE,
  approved_at    timestamptz,
  expires_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pending_email_approvals_token  ON pending_email_approvals (approval_token);
CREATE INDEX IF NOT EXISTS idx_pending_email_approvals_status ON pending_email_approvals (status);

-- ── Per-type approval config ───────────────────────────────────────────────
-- send-email checks this; a missing row defaults to requires_approval = true
-- (safe-by-default). "Approve all" in the review email sets a type to false.
CREATE TABLE IF NOT EXISTS email_type_approval_config (
  email_type        text PRIMARY KEY,
  requires_approval boolean NOT NULL DEFAULT true,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ── DB-overridable templates ───────────────────────────────────────────────
-- getRenderedTemplate() prefers an active DB row, else falls back to the
-- hardcoded template in the function. Optional, but referenced on every send.
CREATE TABLE IF NOT EXISTS email_templates (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_key     text NOT NULL,
  subject_template text,
  html_template    text,
  text_template    text,
  sender_type      text DEFAULT 'team',
  is_active        boolean NOT NULL DEFAULT true,
  version          integer NOT NULL DEFAULT 1,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_email_templates_key_active ON email_templates (template_key, is_active, version DESC);

-- ── Vendor usage log ───────────────────────────────────────────────────────
-- Fire-and-forget cost logging written after each successful send.
CREATE TABLE IF NOT EXISTS api_usage_log (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor             text,
  category           text,
  endpoint           text,
  units              numeric,
  unit_type          text,
  estimated_cost_usd numeric,
  metadata           jsonb,
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- RLS on (project guard: enable on all tables). The edge functions use the
-- service-role key, which bypasses RLS, so no permissive policies are added —
-- these tables hold internal/outbound mail state and stay server-only.
ALTER TABLE pending_email_approvals   ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_type_approval_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_templates           ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_usage_log             ENABLE ROW LEVEL SECURITY;
