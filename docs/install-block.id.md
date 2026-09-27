1. **Tambahkan marketplace** (sekali per mesin). Di terminal:

   ```bash
   claude plugin marketplace add adhibuchori/agent-config-kit
   ```

   Di dalam Claude Code, `/plugin marketplace add adhibuchori/agent-config-kit` melakukan hal yang
   sama.

2. **Pasang agent-core dan satu plugin stack.** Di dalam Claude Code:

   ```text
   /plugin install agent-core@agent-config-kit
   /plugin install agent-fe-nextjs@agent-config-kit
   ```

   Ganti `agent-fe-nextjs` dengan plugin stack yang cocok untuk repo Anda. Memasang plugin stack
   juga memasang agent-core, karena setiap plugin stack bergantung padanya. Jika perintah barunya
   tidak muncul, mulai ulang Claude Code.

3. **Jalankan setup di repo Anda**, untuk plugin stack yang Anda pasang:

   ```text
   /agent-fe-nextjs:setup
   ```

   Setup mengajukan beberapa pertanyaan, satu per satu, masing-masing dengan jawaban yang
   disarankan. Lalu setup menampilkan dry run dari setiap file yang akan ditulis, dan baru menulis
   setelah Anda membalas **go**. Commit file-file barunya bersama `.claude/agent-config-kit.lock`:
   lock itulah yang menyalakan hook untuk semua orang yang meng-clone repo.

**Pembaruan** baru sampai ke Anda saat versi sebuah plugin dinaikkan. Jalankan
`claude plugin marketplace update agent-config-kit`, lalu
`claude plugin update <plugin>@agent-config-kit`, mulai ulang Claude Code, dan jalankan
`/<plugin>:sync` di setiap repo.
