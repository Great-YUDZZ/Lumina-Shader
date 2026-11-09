# Lumina Shader v1.4

Paket shader native berbasis WebGPU Shading Language (WGSL) untuk Horizon Client (Shader API 0.1).

---

## Latar Belakang

Lumina Shader dibuat karena sebagian besar shader pack yang ada di Horizon Client terasa terlalu berat untuk dijalankan secara lancar di laptop dengan kartu grafis terintegrasi (iGPU), seperti AMD Ryzen 5 6600H dengan Radeon 660M. 

Banyak shader pack menyebabkan penurunan frame rate yang tajam (drop hingga 20 sampai 30 FPS), terutama di bioma yang padat seperti Jungle atau saat menampilkan efek kabut dan volumetric lights. Proyek ini dibangun dari nol dengan fokus utama pada efisiensi rendering, pengoptimalan alur komputasi GPU, serta menjaga target performa stabil 60 FPS pada resolusi 1920x1200 tanpa mengorbankan estetika visual modern.

---

## Catatan Rilis Versi 1.4

Rilis versi 1.4 membawa upgrade visual besar pada sistem awan, langit, godrays, dan air realistis:
- **Awan Volumetrik Alami & Realistis**: Menggantikan awan kotak vanilla dengan awan prosedural 4 oktaf FBM dan domain warping. Memiliki volume 3D, self-shadowing, silver lining di tepian matahari, pendaran jingga senja, dan kelabu saat hujan.
- **Matahari Realistis & Oklusi Awan**: Matahari bulat dengan limb darkening dan korona yang dapat tertutup secara alami saat gumpalan awan melintas di depannya, lengkap dengan peredaman godrays otomatis.
- **Bayangan Awan Dinamis di Daratan (Cloud Shadows)**: Awan memproyeksikan bayangan lembut di atas tanah, bukit, pepohonan, dan permukaan air secara real-time mengikuti arah datangnya sinar matahari.
- **Air Realistis & Underwater Caustics**: Gelombang multi-oktaf (swell diagonal dan riak halus) dengan peredaman LOD di kejauhan, dynamic underwater caustics di dasar perairan dangkal, busa bibir pantai (shoreline foam), penyerapan fisik Beer-Lambert, dan pembenahan alpha blending agar pantulan serta refraksi tampak jernih kontras.
- **Godrays Lebar & Adaptif (Porting Shader Horizon v2)**: Algoritma raymarch radial screen-space dengan sudut tangkapan lebih luas (`smoothstep 0.02..0.45`), opsi sampel dinamis 8 sampai 24 langkah (default 16), jangkauan radial 1.45, dan mask langit presisi tinggi.
- **Optimasi Bandwidth Air Jauh**: Air di atas 64 blok langsung melakukan early-out ke refleksi langit dan kabut tanpa membebani memory bandwidth iGPU.

---

## Fitur Utama

- **Pewarnaan Sinematik Hangat & Golden Hour (ACES Filmic)**: Tone mapping berbasis kurva filmik ACES dengan cahaya Golden Hour keemasan di pagi serta sore hari dan bayangan bertingkat biru-ungu lembut (cool shadow tint). Tampilan bersih tanpa efek vignette yang memotong sudut pandang.
- **Awan Volumetrik & Cloud Shadows**: Awan cumulus 3D organik yang dinamis menutupi matahari dan memancarkan bayangan bergerak di daratan dan permukaan air.
- **Aurora Borealis di Langit Malam**: Langit malam dihiasi tirai Aurora Borealis hijau zamrud ke biru-toska dengan gradasi ungu di bagian atas yang mengalir pelan dan ikut terpantul di permukaan air, dilengkapi dengan taburan bintang berputar.
- **Suasana Hujan Cozy Lo-Fi**: Saat turun hujan, langit dan kabut berubah menjadi biru-abu sejuk lembut (slate-blue) dengan rintik hujan tipis yang tenang, sementara cahaya obor dan lentera memancarkan kehangatan ekstra yang memantul halus di permukaan blok basah.
- **Dynamic Hand & Offhand Torch Light**: Cahaya dinamis saat memegang obor atau lentera di tangan kanan (main hand), tangan kiri (offhand), maupun saat item dilempar ke tanah tanpa perlu menaruh blok. Menggunakan perataan radius per-piksel, efek kedipan api tipis, dan warna akurat per tipe item (Torch kuning hangat, Soul Torch biru sian, Redstone Torch merah, Lava Bucket oranye api, Glowstone emas, dan Amethyst/Ender Chest ungu).
- **Hybrid Volumetric Godrays & Soft Bloom Quarter-Resolution**: Berjalan pada skala 0.25x (1/16 jumlah piksel) dengan tent upsampling untuk memberikan sorot sinar matahari di sela pepohonan dan pendaran cahaya halus pada sumber api/lava tanpa membebani kartu grafis.
- **Air Realistis & Underwater Caustics**: Menampilkan dasar perairan secara transparan dengan distorsi ombak lembut, caustics cahaya matahari bergerak di pasir dangkal, penyerapan warna toska Beer-Lambert, busa pantai, Schlick Fresnel, dan pantulan kilau matahari.
- **Glowing Ores di Tempat Gelap**: Urat mineral pada blok bijih (diamond, gold, redstone, emerald, lapis, copper, iron, quartz, nether gold, ancient debris) memancarkan pendaran cahaya khas di dalam gua gelap, sementara bagian batu/deepslate di sekitarnya tetap gelap alami (batu bara/coal ore sengaja dibiarkan tidak bercahaya).

---

## Cara Pemasangan

### Metode 1: Menggunakan Berkas Paket (.hshader)
1. Unduh berkas `lumina_shader-1.4.hshader` dari menu Releases di repositori ini.
2. Salin berkas tersebut ke dalam folder `shaderpacks/` pada direktori instalasi instance Horizon Client Anda.
3. Buka Horizon Client, masuk ke menu **Options > Video Settings > Shaders > Shader Packs**.
4. Pilih **Lumina Shader** dari daftar.

### Metode 2: Menggunakan Folder Sumber (Unpacked)
1. Unduh atau clone repositori ini.
2. Salin folder `lumina_shader` langsung ke dalam folder `shaderpacks/` pada direktori instalasi instance Horizon Client Anda.
3. Aktifkan shader melalui menu Shader Packs di dalam game.

---

## Pengaturan Tambahan yang Disarankan

Untuk mengaktifkan fitur pencahayaan saat memegang obor di tangan atau tangan kiri:
- Masuk ke menu **Options > Video Settings > Extras**, lalu aktifkan opsi **Dynamic Lights: ON**.

Pengaturan shader dapat disesuaikan langsung di dalam game melalui tombol **Shader Options**:
- **Lighting & Shadows**: Kualitas bayangan, jarak bayangan, kehangatan matahari, kekuatan cahaya blok, dan kekuatan cahaya obor di tangan (`Hand Torch Light`).
- **Sky, Godrays & Fog**: Intensitas godrays, ketebalan kabut pagi/senja/hujan, dan tingkat kegelapan malam.
- **Water & Rain**: Kejernihan air, pantulan kilau matahari pada ombak, dan efek basah saat hujan.
- **Glowing Ores & Emissive**: Tingkat pendaran bijih di gua dan intensitas blok emisi.
- **Bloom & Color Grade**: Kekuatan bloom, eksposur, kontras, dan saturasi warna ACES.

---

## Lisensi

Proyek ini dirilis di bawah lisensi [MIT](LICENSE).
