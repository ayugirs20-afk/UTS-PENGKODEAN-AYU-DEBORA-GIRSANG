import test from "node:test";
import assert from "node:assert/strict";
import { amountInCents, validateVoucher } from "../src/voucher-validation.js";

const accounts = [
  { account_id: 1, is_cash: true },
  { account_id: 2, is_cash: false },
  { account_id: 3, is_cash: false },
];
const completeHeader = {
  reference: "KK-TEST-001",
  trxDate: "2026-10-13",
  description: "Pembayaran pengujian",
};

function validVoucher() {
  return {
    accounts,
    header: { ...completeHeader },
    lines: [
      { account_id: "2", debit: "1000.00", credit: "" },
      { account_id: "1", debit: "", credit: "1000.00" },
    ],
  };
}

test("converts exact rupiah values to integer cents", () => {
  assert.equal(amountInCents("123.45"), 12345);
  assert.equal(amountInCents(""), 0);
  assert.equal(amountInCents("-1"), null);
  assert.equal(amountInCents("1.234"), null);
  assert.equal(amountInCents("90071992547409.92"), null);
});

test("accepts a balanced, complete cash-out voucher", () => {
  const result = validateVoucher(validVoucher());
  assert.equal(result.valid, true);
  assert.equal(result.debit, 100000);
  assert.equal(result.credit, 100000);
});

test("rejects an unbalanced voucher", () => {
  const voucher = validVoucher();
  voucher.lines[1].credit = "900.00";
  const result = validateVoucher(voucher);
  assert.equal(result.state, "TIDAK SEIMBANG");
  assert.equal(result.valid, false);
});

test("rejects missing voucher header fields", () => {
  const voucher = validVoucher();
  voucher.header.reference = "";
  const result = validateVoucher(voucher);
  assert.equal(result.state, "BELUM LENGKAP");
  assert.equal(result.valid, false);
});

test("rejects a line with both debit and credit", () => {
  const voucher = validVoucher();
  voucher.lines[0].credit = "1.00";
  const result = validateVoucher(voucher);
  assert.equal(result.state, "INPUT TIDAK VALID");
  assert.equal(result.valid, false);
});

test("rejects cash debited for a cash-out voucher", () => {
  const voucher = validVoucher();
  voucher.lines[0].account_id = "1";
  voucher.lines[0].debit = "1000.00";
  voucher.lines[1].account_id = "2";
  voucher.lines[1].credit = "1000.00";
  const result = validateVoucher(voucher);
  assert.equal(result.state, "INPUT TIDAK VALID");
  assert.equal(result.valid, false);
});

test("rejects account IDs not present in the active chart", () => {
  const voucher = validVoucher();
  voucher.lines[0].account_id = "999";
  const result = validateVoucher(voucher);
  assert.equal(result.valid, false);
});
