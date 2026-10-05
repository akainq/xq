// The website of XQ: copy buttons on code, the section being read in the contents, the visitor's platform among the
// downloads, the contents on narrow screens.
(() => {
  for (const pre of document.querySelectorAll("pre.code")) {
    const b = document.createElement("button");
    b.className = "copy";
    b.type = "button";
    b.textContent = "Copy";
    b.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText((pre.querySelector("code") ?? pre).innerText);
        b.textContent = "Copied";
      } catch {
        b.textContent = "Select and copy";
      }
      setTimeout(() => (b.textContent = "Copy"), 1500);
    });
    pre.appendChild(b);
  }

  // The page in the header.
  const page = document.body.dataset.page;
  if (page) for (const a of document.querySelectorAll(".top nav a")) if (a.getAttribute("href") === page) a.classList.add("here");

  // The contents: the toggle on narrow screens, and the section being read.
  const toc = document.querySelector(".toc");
  if (toc) {
    const button = toc.querySelector(".toc-toggle");
    button.addEventListener("click", () => {
      const open = toc.classList.toggle("open");
      button.setAttribute("aria-expanded", String(open));
    });
    toc.addEventListener("click", (e) => {
      if (e.target.closest("a")) toc.classList.remove("open");
    });
    const links = new Map([...toc.querySelectorAll("a")].map((a) => [a.getAttribute("href").slice(1), a]));
    const heads = [...document.querySelectorAll(".content h2[id], .content h3[id]")];
    let current = null;
    const mark = () => {
      let id = heads.length ? heads[0].id : null;
      for (const h of heads) if (h.getBoundingClientRect().top < 120) id = h.id;
      if (id === current) return;
      current = id;
      for (const a of links.values()) a.classList.remove("here");
      const a = links.get(id);
      if (a) {
        a.classList.add("here");
        const nav = toc.querySelector("nav");
        const r = a.getBoundingClientRect(), n = toc.getBoundingClientRect();
        if (r.top < n.top || r.bottom > n.bottom) a.scrollIntoView({ block: "nearest" });
      }
    };
    document.addEventListener("scroll", mark, { passive: true });
    mark();
  }

  // The visitor's platform first among the downloads.
  const ua = navigator.userAgent;
  const os = /Windows/.test(ua) ? "windows" : /Mac OS X|Macintosh/.test(ua) ? "macos" : /Linux/.test(ua) ? (/aarch64|arm64/i.test(ua) ? "linux-arm" : "linux") : null;
  if (os) {
    const card = document.querySelector(`.dl[data-os="${os}"]`);
    if (card && !card.classList.contains("soon")) card.classList.add("mine");
  }
})();
