// Progressive enhancement: everything works as plain links and forms without JS.
(() => {
  // change of locale / batch size / text toggle regenerates right away
  document.querySelectorAll("[data-autosubmit]").forEach((el) => {
    el.addEventListener("change", () => {
      const batch = el.form.querySelector("#batch");
      if (batch) batch.value = 1;
      el.form.requestSubmit();
    });
  });

  // "Load batch N" appends the next batch, rendered by the server, to the table
  const next = document.getElementById("next-batch");
  const rows = document.getElementById("rows");
  const csv = document.getElementById("csv");
  const status = document.getElementById("status");
  if (!next || !rows) return;

  next.addEventListener("click", async (event) => {
    event.preventDefault();
    if (next.getAttribute("aria-busy") === "true") return;
    const n = Number(next.dataset.next);
    next.setAttribute("aria-busy", "true");
    status.textContent = `Generating batch ${n}…`;
    try {
      const response = await fetch(next.dataset.src.replace("__N__", n));
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const template = document.createElement("template");
      template.innerHTML = await response.text();
      const head = template.content.querySelector(".batch-head");
      head?.classList.add("is-new");
      rows.append(template.content);
      next.dataset.next = n + 1;
      next.textContent = `Load batch ${n + 1}`;
      next.href = next.href.replace(/([?&]batch=)\d+/, `$1${n + 1}`);
      if (csv) csv.href = csv.dataset.base.replace("__N__", n);
      status.textContent = `Batch ${n} added.`;
    } catch (err) {
      status.textContent = `Batch ${n} could not be generated (${err.message}). Press the button to try again.`;
    } finally {
      next.removeAttribute("aria-busy");
    }
  });
})();
