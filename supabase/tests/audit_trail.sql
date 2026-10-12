BEGIN;

DO $$
DECLARE
    v_user UUID;
    v_cash_account BIGINT;
    v_expense_account BIGINT;
    v_header_id BIGINT;
    v_reversal_id BIGINT;
    v_reference TEXT := 'UTS-AUDIT-' || substr(gen_random_uuid()::TEXT, 1, 8);
    v_checksum TEXT;
    v_audit_count BIGINT;
    v_blocked BOOLEAN;
    v_invalid_reference TEXT := 'UTS-BALANCE-' || substr(gen_random_uuid()::TEXT, 1, 8);
BEGIN
    SELECT id
    INTO v_user
    FROM auth.users
    ORDER BY created_at
    LIMIT 1;

    IF v_user IS NULL THEN
        v_user := gen_random_uuid();
        INSERT INTO auth.users (
            id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            created_at,
            updated_at
        )
        VALUES (
            v_user,
            'authenticated',
            'authenticated',
            'audit-test-' || v_user::TEXT || '@example.invalid',
            '',
            clock_timestamp(),
            '{"provider":"email","providers":["email"]}'::JSONB,
            '{}'::JSONB,
            clock_timestamp(),
            clock_timestamp()
        );
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_user::TEXT, TRUE);

    SELECT account_id
    INTO v_cash_account
    FROM public.chart_of_accounts
    WHERE account_code = '1-1100' AND is_cash AND is_active;

    SELECT account_id
    INTO v_expense_account
    FROM public.chart_of_accounts
    WHERE account_code = '5-2100' AND NOT is_cash AND is_active;

    IF v_cash_account IS NULL OR v_expense_account IS NULL THEN
        RAISE EXCEPTION 'Akun kas dan beban seed tidak ditemukan';
    END IF;

    v_header_id := public.create_cash_voucher(
        v_reference,
        CURRENT_DATE,
        'Transaksi uji audit trail (akan di-ROLLBACK)',
        jsonb_build_array(
            jsonb_build_object(
                'account_id', v_expense_account,
                'debit', 12500.00,
                'credit', 0
            ),
            jsonb_build_object(
                'account_id', v_cash_account,
                'debit', 0,
                'credit', 12500.00
            )
        )
    );

    SELECT hash_checksum
    INTO v_checksum
    FROM public.journal_headers
    WHERE header_id = v_header_id;

    IF v_checksum IS NULL
       OR NOT public.verify_voucher_checksum(v_header_id) THEN
        RAISE EXCEPTION 'Checksum voucher awal gagal diverifikasi';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.journal_headers
        WHERE header_id = v_header_id
          AND created_by = v_user
          AND created_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Metadata pembuat atau waktu server tidak tercatat';
    END IF;

    SELECT COUNT(*)
    INTO v_audit_count
    FROM public.get_voucher_audit(v_header_id);

    IF v_audit_count < 4 THEN
        RAISE EXCEPTION 'Audit log tidak mencatat seluruh insert dan posting';
    END IF;

    v_blocked := FALSE;
    BEGIN
        UPDATE public.journal_headers
        SET description = 'Perubahan tidak sah'
        WHERE header_id = v_header_id;
    EXCEPTION WHEN SQLSTATE '55000' THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'UPDATE header POSTED tidak ditolak';
    END IF;

    v_blocked := FALSE;
    BEGIN
        DELETE FROM public.journal_headers
        WHERE header_id = v_header_id;
    EXCEPTION WHEN SQLSTATE '55000' THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'DELETE header POSTED tidak ditolak';
    END IF;

    v_blocked := FALSE;
    BEGIN
        UPDATE public.journal_lines
        SET debit = debit + 1
        WHERE header_id = v_header_id
          AND debit > 0;
    EXCEPTION WHEN SQLSTATE '55000' THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'UPDATE baris jurnal POSTED tidak ditolak';
    END IF;

    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.journal_lines
            (header_id, account_id, debit, credit)
        VALUES (v_header_id, v_expense_account, 1, 0);
    EXCEPTION WHEN SQLSTATE '55000' THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'INSERT baris ke jurnal POSTED tidak ditolak';
    END IF;

    v_blocked := FALSE;
    BEGIN
        DELETE FROM public.journal_lines
        WHERE header_id = v_header_id;
    EXCEPTION WHEN SQLSTATE '55000' THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'DELETE baris jurnal POSTED tidak ditolak';
    END IF;

    v_blocked := FALSE;
    BEGIN
        UPDATE public.audit_log
        SET action = action
        WHERE audit_id = (
            SELECT MIN(audit_id)
            FROM public.audit_log
            WHERE table_name = 'journal_headers'
              AND record_id = v_header_id
        );
    EXCEPTION WHEN SQLSTATE '55000' THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'UPDATE audit_log tidak ditolak';
    END IF;

    v_blocked := FALSE;
    BEGIN
        DELETE FROM public.audit_log
        WHERE audit_id = (
            SELECT MIN(audit_id)
            FROM public.audit_log
            WHERE table_name = 'journal_headers'
              AND record_id = v_header_id
        );
    EXCEPTION WHEN SQLSTATE '55000' THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'DELETE audit_log tidak ditolak';
    END IF;

    v_blocked := FALSE;
    BEGIN
        PERFORM public.create_cash_voucher(
            v_invalid_reference,
            CURRENT_DATE,
            'Uji penolakan jurnal tidak seimbang',
            jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_expense_account,
                    'debit', 100,
                    'credit', 0
                ),
                jsonb_build_object(
                    'account_id', v_cash_account,
                    'debit', 0,
                    'credit', 90
                )
            )
        );
    EXCEPTION WHEN check_violation THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked OR EXISTS (
        SELECT 1
        FROM public.journal_headers
        WHERE reference_no = v_invalid_reference
    ) THEN
        RAISE EXCEPTION 'Voucher tidak seimbang tidak ditolak secara atomik';
    END IF;

    v_reversal_id := public.reverse_cash_voucher(
        v_header_id,
        'Tes pembalikan audit trail'
    );

    IF NOT public.verify_voucher_checksum(v_header_id)
       OR NOT public.verify_voucher_checksum(v_reversal_id) THEN
        RAISE EXCEPTION 'Checksum jurnal asal atau pembalik berubah';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.journal_headers
        WHERE header_id = v_reversal_id
          AND posting_status = 'POSTED'
          AND reversal_of = v_header_id
    ) THEN
        RAISE EXCEPTION 'Jurnal pembalik tidak terhubung ke jurnal asal';
    END IF;

    v_blocked := FALSE;
    BEGIN
        PERFORM public.reverse_cash_voucher(
            v_header_id,
            'Tes pembalikan duplikat'
        );
    EXCEPTION WHEN raise_exception THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'Pembalikan kedua tidak ditolak';
    END IF;
END;
$$;

ROLLBACK;
