/*
 * Homing UI 原型（暫定標準）— 零依賴互動：
 *  - 頂端按鈕切換「聊天室／首頁」
 *  - 點底部 tab 切換（僅首頁三個 tab 的外觀回饋；無真實分頁內容）
 * 修改：直接加新的 page / 即在 index.html 加 <main class="page" id="...">。
 */
const buttons = document.querySelectorAll('.switcher button');
const pages = document.querySelectorAll('.page');

buttons.forEach((btn) => {
  btn.addEventListener('click', () => {
    const target = btn.dataset.page;
    buttons.forEach((b) => b.classList.toggle('active', b === btn));
    pages.forEach((p) => p.classList.toggle('active', p.id === target));
  });
});

document.querySelectorAll('.bottomnav .tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.bottomnav .tab').forEach((t) => t.classList.remove('active'));
    tab.classList.add('active');
  });
});
