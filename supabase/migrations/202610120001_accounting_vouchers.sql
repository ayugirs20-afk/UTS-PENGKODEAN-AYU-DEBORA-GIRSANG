CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated;

CREATE TABLE public.chart_of_accounts (
    account_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_code VARCHAR(20) NOT NULL UNIQUE,
    account_name VARCHAR(150) NOT NULL,
    normal_balance VARCHAR(6) NOT NULL
        CHECK (normal_balance IN ('DEBIT', 'CREDIT')),
    report_class VARCHAR(20) NOT NULL
        CHECK (report_class IN ('BALANCE_SHEET', 'INCOME_STATEMENT')),
    is_cash BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE public.journal_headers (
    header_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trx_date DATE NOT NULL,
    reference_no VARCHAR(50) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    posting_status VARCHAR(10) NOT NULL DEFAULT 'DRAFT'
        CHECK (posting_status IN ('DRAFT', 'POSTED')),
    created_by UUID NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    hash_checksum TEXT,
    reversal_of BIGINT UNIQUE
        REFERENCES public.journal_headers (header_id) ON DELETE RESTRICT,
    CONSTRAINT chk_posted_has_hash
        CHECK (posting_status <> 'POSTED' OR hash_checksum IS NOT NULL)
);

CREATE TABLE public.journal_lines (
    line_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    header_id BIGINT NOT NULL
        REFERENCES public.journal_headers (header_id) ON DELETE RESTRICT,
    account_id BIGINT NOT NULL
        REFERENCES public.chart_of_accounts (account_id) ON DELETE RESTRICT,
    debit NUMERIC(18,2) NOT NULL DEFAULT 0,
    credit NUMERIC(18,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_debit_nonnegative CHECK (debit >= 0),
    CONSTRAINT chk_credit_nonnegative CHECK (credit >= 0),
    CONSTRAINT chk_exactly_one_side
        CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
);

CREATE INDEX idx_journal_headers_owner_date
    ON public.journal_headers (created_by, trx_date DESC);
CREATE INDEX idx_journal_lines_header
    ON public.journal_lines (header_id);
CREATE INDEX idx_journal_lines_account
    ON public.journal_lines (account_id);

INSERT INTO public.chart_of_accounts
    (account_code, account_name, normal_balance, report_class, is_cash)
VALUES
    ('1-1100', 'Kas', 'DEBIT', 'BALANCE_SHEET', TRUE),
    ('1-1200', 'Bank', 'DEBIT', 'BALANCE_SHEET', TRUE),
    ('2-1100', 'Utang Usaha', 'CREDIT', 'BALANCE_SHEET', FALSE),
    ('5-2100', 'Beban Listrik', 'DEBIT', 'INCOME_STATEMENT', FALSE),
    ('5-2200', 'Beban Perlengkapan', 'DEBIT', 'INCOME_STATEMENT', FALSE)
ON CONFLICT (account_code) DO NOTHING;

CREATE TABLE public.audit_log (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id BIGINT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB,
    changed_by UUID,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX idx_audit_log_record
    ON public.audit_log (table_name, record_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.fn_compute_journal_hash(p_header_id BIGINT)
RETURNS TEXT
LANGUAGE SQL
STABLE
SET search_path = public, extensions, pg_temp
AS $$
    SELECT encode(
        digest(
            convert_to(
                jsonb_build_object(
                    'header_id', h.header_id,
                    'trx_date', h.trx_date,
                    'reference_no', h.reference_no,
                    'description', h.description,
                    'created_by', h.created_by,
                    'created_at', h.created_at,
                    'lines', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'line_id', l.line_id,
                                'account_id', l.account_id,
                                'debit', l.debit,
                                'credit', l.credit
                            ) ORDER BY l.line_id
                        )
                        FROM public.journal_lines AS l
                        WHERE l.header_id = h.header_id
                    ), '[]'::JSONB)
                )::TEXT,
                'UTF8'
            ),
            'sha256'
        ),
        'hex'
    )
    FROM public.journal_headers AS h
    WHERE h.header_id = p_header_id;
$$;

CREATE OR REPLACE FUNCTION public.fn_audit_journal_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_record_id BIGINT;
    v_actor UUID := auth.uid();
BEGIN
    IF TG_TABLE_NAME = 'journal_headers' THEN
        IF TG_OP = 'DELETE' THEN
            v_record_id := OLD.header_id;
            v_actor := COALESCE(v_actor, OLD.created_by);
            INSERT INTO public.audit_log
                (table_name, record_id, action, old_data, changed_by)
            VALUES
                (TG_TABLE_NAME, v_record_id, TG_OP, to_jsonb(OLD), v_actor);
            RETURN OLD;
        ELSIF TG_OP = 'UPDATE' THEN
            v_record_id := NEW.header_id;
            v_actor := COALESCE(v_actor, NEW.created_by);
            INSERT INTO public.audit_log
                (table_name, record_id, action, old_data, new_data, changed_by)
            VALUES
                (TG_TABLE_NAME, v_record_id, TG_OP,
                 to_jsonb(OLD), to_jsonb(NEW), v_actor);
            RETURN NEW;
        ELSE
            v_record_id := NEW.header_id;
            v_actor := COALESCE(v_actor, NEW.created_by);
            INSERT INTO public.audit_log
                (table_name, record_id, action, new_data, changed_by)
            VALUES
                (TG_TABLE_NAME, v_record_id, TG_OP, to_jsonb(NEW), v_actor);
            RETURN NEW;
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_record_id := OLD.line_id;
        INSERT INTO public.audit_log
            (table_name, record_id, action, old_data, changed_by)
        VALUES
            (TG_TABLE_NAME, v_record_id, TG_OP, to_jsonb(OLD), v_actor);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        v_record_id := NEW.line_id;
        INSERT INTO public.audit_log
            (table_name, record_id, action, old_data, new_data, changed_by)
        VALUES
            (TG_TABLE_NAME, v_record_id, TG_OP,
             to_jsonb(OLD), to_jsonb(NEW), v_actor);
        RETURN NEW;
    ELSE
        v_record_id := NEW.line_id;
        INSERT INTO public.audit_log
            (table_name, record_id, action, new_data, changed_by)
        VALUES
            (TG_TABLE_NAME, v_record_id, TG_OP, to_jsonb(NEW), v_actor);
        RETURN NEW;
    END IF;
END;
$$;

CREATE TRIGGER trg_audit_journal_headers
AFTER INSERT OR UPDATE OR DELETE ON public.journal_headers
FOR EACH ROW EXECUTE FUNCTION public.fn_audit_journal_change();

CREATE TRIGGER trg_audit_journal_lines
AFTER INSERT OR UPDATE OR DELETE ON public.journal_lines
FOR EACH ROW EXECUTE FUNCTION public.fn_audit_journal_change();

CREATE OR REPLACE FUNCTION public.fn_block_posted_journal_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_status TEXT;
BEGIN
    IF TG_TABLE_NAME = 'journal_headers' THEN
        IF TG_OP IN ('UPDATE', 'DELETE')
           AND OLD.posting_status = 'POSTED' THEN
            RAISE EXCEPTION
                'Jurnal POSTED tidak dapat diubah/dihapus; gunakan jurnal pembalik'
                USING ERRCODE = '55000';
        END IF;

        IF TG_OP = 'UPDATE' THEN
            IF NEW.created_by IS DISTINCT FROM OLD.created_by
               OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
                RAISE EXCEPTION 'created_by dan created_at tidak boleh diubah'
                    USING ERRCODE = '55000';
            END IF;

            IF OLD.posting_status = 'DRAFT'
               AND NEW.posting_status = 'POSTED'
               AND (
                   NEW.header_id IS DISTINCT FROM OLD.header_id
                   OR NEW.trx_date IS DISTINCT FROM OLD.trx_date
                   OR NEW.reference_no IS DISTINCT FROM OLD.reference_no
                   OR NEW.description IS DISTINCT FROM OLD.description
                   OR NEW.reversal_of IS DISTINCT FROM OLD.reversal_of
                   OR NEW.hash_checksum IS NULL
               ) THEN
                RAISE EXCEPTION
                    'Perubahan DRAFT ke POSTED hanya boleh mengisi status dan checksum'
                    USING ERRCODE = '55000';
            END IF;
        END IF;

        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT posting_status INTO v_status
        FROM public.journal_headers
        WHERE header_id = OLD.header_id;
        IF v_status = 'POSTED' THEN
            RAISE EXCEPTION
                'Baris milik jurnal POSTED tidak dapat diubah/dihapus'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT posting_status INTO v_status
        FROM public.journal_headers
        WHERE header_id = NEW.header_id;
        IF v_status = 'POSTED' THEN
            RAISE EXCEPTION
                'Baris tidak dapat ditambahkan ke jurnal POSTED'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_immutable_journal_headers
BEFORE UPDATE OR DELETE ON public.journal_headers
FOR EACH ROW EXECUTE FUNCTION public.fn_block_posted_journal_changes();

CREATE TRIGGER trg_immutable_journal_lines
BEFORE INSERT OR UPDATE OR DELETE ON public.journal_lines
FOR EACH ROW EXECUTE FUNCTION public.fn_block_posted_journal_changes();

CREATE OR REPLACE FUNCTION public.create_cash_voucher(
    p_reference_no TEXT,
    p_trx_date DATE,
    p_description TEXT,
    p_lines JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_header_id BIGINT;
    v_line_count BIGINT;
    v_debit NUMERIC(18,2);
    v_credit NUMERIC(18,2);
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Autentikasi diperlukan untuk membuat voucher'
            USING ERRCODE = '28000';
    END IF;
    IF p_reference_no IS NULL OR length(btrim(p_reference_no)) = 0
       OR length(p_reference_no) > 50 THEN
        RAISE EXCEPTION 'Nomor bukti wajib diisi maksimal 50 karakter';
    END IF;
    IF p_trx_date IS NULL THEN
        RAISE EXCEPTION 'Tanggal transaksi wajib diisi';
    END IF;
    IF p_description IS NULL OR length(btrim(p_description)) = 0 THEN
        RAISE EXCEPTION 'Keterangan transaksi wajib diisi';
    END IF;
    IF jsonb_typeof(p_lines) IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_lines) < 2 THEN
        RAISE EXCEPTION 'Voucher harus memiliki minimal dua baris jurnal';
    END IF;

    INSERT INTO public.journal_headers
        (trx_date, reference_no, description, posting_status, created_by)
    VALUES
        (p_trx_date, btrim(p_reference_no), btrim(p_description), 'DRAFT', v_user)
    RETURNING header_id INTO v_header_id;

    INSERT INTO public.journal_lines (header_id, account_id, debit, credit)
    SELECT
        v_header_id,
        (line->>'account_id')::BIGINT,
        (line->>'debit')::NUMERIC,
        (line->>'credit')::NUMERIC
    FROM jsonb_array_elements(p_lines) AS line;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_lines) AS line
        WHERE (line->>'debit')::NUMERIC <> round((line->>'debit')::NUMERIC, 2)
           OR (line->>'credit')::NUMERIC <> round((line->>'credit')::NUMERIC, 2)
    ) THEN
        RAISE EXCEPTION 'Nominal hanya boleh memiliki maksimal dua angka desimal'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.journal_lines AS l
        JOIN public.chart_of_accounts AS a USING (account_id)
        WHERE l.header_id = v_header_id
          AND NOT a.is_active
    ) THEN
        RAISE EXCEPTION 'Akun tidak aktif tidak dapat digunakan'
            USING ERRCODE = '23514';
    END IF;

    SELECT COUNT(*), COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_line_count, v_debit, v_credit
    FROM public.journal_lines
    WHERE header_id = v_header_id;

    IF v_line_count < 2 OR v_debit <= 0 OR v_debit <> v_credit THEN
        RAISE EXCEPTION
            'Jurnal tidak seimbang atau tidak valid: baris %, debit %, kredit %',
            v_line_count, v_debit, v_credit
            USING ERRCODE = '23514';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.journal_lines AS l
        JOIN public.chart_of_accounts AS a USING (account_id)
        WHERE l.header_id = v_header_id
          AND a.is_cash
          AND l.credit > 0
    ) OR EXISTS (
        SELECT 1
        FROM public.journal_lines AS l
        JOIN public.chart_of_accounts AS a USING (account_id)
        WHERE l.header_id = v_header_id
          AND a.is_cash
          AND l.debit > 0
    ) THEN
        RAISE EXCEPTION
            'Kas keluar harus mengkredit akun kas/bank dan tidak boleh mendebitnya'
            USING ERRCODE = '23514';
    END IF;

    UPDATE public.journal_headers
    SET hash_checksum = public.fn_compute_journal_hash(v_header_id),
        posting_status = 'POSTED'
    WHERE header_id = v_header_id;

    RETURN v_header_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_cash_voucher(
    p_header_id BIGINT,
    p_reason TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_original public.journal_headers%ROWTYPE;
    v_reversal_id BIGINT;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Autentikasi diperlukan untuk membalik jurnal'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_original
    FROM public.journal_headers
    WHERE header_id = p_header_id
      AND created_by = v_user
    FOR UPDATE;

    IF NOT FOUND OR v_original.posting_status <> 'POSTED' THEN
        RAISE EXCEPTION 'Jurnal milik pengguna dan berstatus POSTED diperlukan';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.journal_headers WHERE reversal_of = p_header_id
    ) THEN
        RAISE EXCEPTION 'Jurnal ini sudah memiliki jurnal pembalik';
    END IF;

    INSERT INTO public.journal_headers
        (trx_date, reference_no, description, posting_status, created_by, reversal_of)
    VALUES
        (
            CURRENT_DATE,
            left('REV-' || v_original.reference_no || '-' ||
                 substr(gen_random_uuid()::TEXT, 1, 8), 50),
            'Pembalik ' || v_original.reference_no || ': ' ||
                COALESCE(NULLIF(btrim(p_reason), ''), 'koreksi'),
            'DRAFT',
            v_user,
            p_header_id
        )
    RETURNING header_id INTO v_reversal_id;

    INSERT INTO public.journal_lines (header_id, account_id, debit, credit)
    SELECT v_reversal_id, account_id, credit, debit
    FROM public.journal_lines
    WHERE header_id = p_header_id
    ORDER BY line_id;

    UPDATE public.journal_headers
    SET hash_checksum = public.fn_compute_journal_hash(v_reversal_id),
        posting_status = 'POSTED'
    WHERE header_id = v_reversal_id;

    RETURN v_reversal_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_voucher_audit(p_header_id BIGINT)
RETURNS TABLE (
    table_name TEXT,
    record_id BIGINT,
    action TEXT,
    changed_by UUID,
    changed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
BEGIN
    IF v_user IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.journal_headers
        WHERE header_id = p_header_id AND created_by = v_user
    ) THEN
        RAISE EXCEPTION 'Voucher tidak ditemukan atau akses ditolak'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT a.table_name, a.record_id, a.action, a.changed_by, a.changed_at
    FROM public.audit_log AS a
    WHERE (a.table_name = 'journal_headers' AND a.record_id = p_header_id)
       OR (a.table_name = 'journal_lines'
           AND COALESCE(a.new_data, a.old_data)->>'header_id' = p_header_id::TEXT)
    ORDER BY a.changed_at, a.audit_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_voucher_checksum(p_header_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_stored TEXT;
    v_computed TEXT;
BEGIN
    SELECT hash_checksum INTO v_stored
    FROM public.journal_headers
    WHERE header_id = p_header_id AND created_by = auth.uid()
      AND posting_status = 'POSTED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher posted tidak ditemukan atau akses ditolak'
            USING ERRCODE = '42501';
    END IF;
    v_computed := public.fn_compute_journal_hash(p_header_id);
    RETURN v_stored = v_computed;
END;
$$;

ALTER TABLE public.chart_of_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_headers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated users read active accounts"
    ON public.chart_of_accounts FOR SELECT TO authenticated
    USING (is_active);

CREATE POLICY "users read their own journal headers"
    ON public.journal_headers FOR SELECT TO authenticated
    USING (created_by = auth.uid());

CREATE POLICY "users read their own journal lines"
    ON public.journal_lines FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.journal_headers AS h
            WHERE h.header_id = journal_lines.header_id
              AND h.created_by = auth.uid()
        )
    );

REVOKE ALL ON public.audit_log FROM anon, authenticated;
REVOKE ALL ON public.chart_of_accounts FROM anon, authenticated;
REVOKE ALL ON public.journal_headers FROM anon, authenticated;
REVOKE ALL ON public.journal_lines FROM anon, authenticated;
REVOKE ALL ON public.audit_log FROM anon, authenticated;
GRANT SELECT ON public.chart_of_accounts TO authenticated;
GRANT SELECT ON public.journal_headers TO authenticated;
GRANT SELECT ON public.journal_lines TO authenticated;

REVOKE ALL ON FUNCTION public.fn_compute_journal_hash(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_journal_change() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_block_posted_journal_changes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_cash_voucher(TEXT, DATE, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_cash_voucher(BIGINT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_voucher_audit(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_voucher_checksum(BIGINT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_cash_voucher(TEXT, DATE, TEXT, JSONB)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_cash_voucher(BIGINT, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_voucher_audit(BIGINT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_voucher_checksum(BIGINT)
    TO authenticated;
