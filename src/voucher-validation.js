export function amountInCents(value) {
  if (value === "") return 0;
  if (typeof value !== "string" || !/^\d+(?:\.\d{1,2})?$/.test(value)) return null;

  const [whole, fraction = ""] = value.split(".");
  const amount = Number(whole) * 100 + Number((fraction + "00").slice(0, 2));
  return Number.isSafeInteger(amount) ? amount : null;
}

export function validateVoucher({ lines, accounts, header }) {
  const debitAmounts = lines.map((line) => amountInCents(line.debit));
  const creditAmounts = lines.map((line) => amountInCents(line.credit));
  const amountsValid = debitAmounts.every((amount) => amount !== null)
    && creditAmounts.every((amount) => amount !== null);
  const debit = debitAmounts.reduce((sum, amount) => sum + (amount ?? 0), 0);
  const credit = creditAmounts.reduce((sum, amount) => sum + (amount ?? 0), 0);
  const totalsSafe = Number.isSafeInteger(debit) && Number.isSafeInteger(credit);
  const headerComplete = Object.values(header).every((value) => String(value ?? "").trim() !== "");
  const rowIncomplete = lines.some((line, index) =>
    !line.account_id
    || (debitAmounts[index] === 0 && creditAmounts[index] === 0));
  const sideConflict = lines.some((line, index) =>
    debitAmounts[index] > 0 && creditAmounts[index] > 0);
  const linesValid = lines.length >= 2 && lines.every((line, index) => {
    const accountExists = accounts.some(
      (account) => String(account.account_id) === String(line.account_id),
    );
    return accountExists
      && debitAmounts[index] !== null
      && creditAmounts[index] !== null
      && ((debitAmounts[index] > 0) !== (creditAmounts[index] > 0));
  });
  const cashCredit = lines.some((line, index) => {
    const account = accounts.find(
      (item) => String(item.account_id) === String(line.account_id),
    );
    return account?.is_cash && creditAmounts[index] > 0;
  });
  const cashDebit = lines.some((line, index) => {
    const account = accounts.find(
      (item) => String(item.account_id) === String(line.account_id),
    );
    return account?.is_cash && debitAmounts[index] > 0;
  });
  const balanced = totalsSafe && debit > 0 && debit === credit;
  const incomplete = !headerComplete || rowIncomplete || lines.length < 2;
  const invalid = !amountsValid || !totalsSafe || sideConflict || !linesValid
    || cashDebit || !cashCredit;
  const valid = !incomplete && !invalid && balanced;
  const messages = [];

  if (!headerComplete) messages.push("Nomor bukti, tanggal, dan keterangan wajib diisi.");
  if (lines.length < 2) messages.push("Minimal dua baris jurnal.");
  if (rowIncomplete) messages.push("Lengkapi akun dan nominal pada setiap baris.");
  if (!amountsValid || !totalsSafe) {
    messages.push("Nominal harus nonnegatif, memiliki maksimal dua angka desimal, dan berada dalam rentang aman.");
  }
  if (sideConflict) messages.push("Satu baris tidak boleh memiliki debit dan kredit sekaligus.");
  if (!balanced) messages.push("Total debit dan kredit harus sama serta lebih dari nol.");
  if (!cashCredit || cashDebit) {
    messages.push("Akun kas/bank wajib dikredit dan tidak boleh didebit untuk voucher kas keluar.");
  }

  return {
    debit,
    credit,
    valid,
    state: incomplete ? "BELUM LENGKAP" : invalid ? "INPUT TIDAK VALID" : "TIDAK SEIMBANG",
    messages,
  };
}
