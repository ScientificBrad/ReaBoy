document.querySelectorAll('[data-copy]').forEach(button => {
  button.addEventListener('click', async () => {
    const code = document.getElementById(button.dataset.copy);
    const status = document.getElementById('copy-status');
    try {
      await navigator.clipboard.writeText(code.textContent.trim());
      status.textContent = 'Install command copied.';
      button.textContent = 'Copied';
      setTimeout(() => { status.textContent = ''; button.textContent = 'Copy command'; }, 2500);
    } catch {
      const range = document.createRange();
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection.removeAllRanges(); selection.addRange(range);
      status.textContent = 'Command selected. Copy it with Ctrl+C.';
    }
  });
});
const video = document.getElementById('boot-video');
if (video && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  video.autoplay = false; video.pause();
}
