# Lumina Shader v1.1

Paket shader native berbasis WebGPU Shading Language (WGSL) untuk **Horizon Client** (Shader API 0.1), dioptimalkan untuk performa 60 FPS pada kartu grafis terintegrasi (iGPU) seperti AMD Radeon 660M/680M.

## Latar Belakang
Shader ini dibuat karena sebagian besar shader pack yang tersedia untuk Horizon Client terasa terlalu berat untuk dijalankan di laptop pengembang. Lumina Shader dirancang dari awal dengan efisiensi tinggi agar visual tetap modern dan sinematik tanpa penurunan frame rate yang tajam.

## Status Rilis
Ini merupakan rilis versi awal (v1.1), sehingga kemungkinan masih terdapat bug atau elemen visual yang belum sempurna di beberapa kondisi lingkungan.

## Fitur Utama
- **Warm Cinematic Grading & Rich Golden Hour**: ACES filmic tone mapping dengan bayangan bersuhu dingin lembut dan cahaya Golden Hour keemasan di pagi serta sore hari.
- **Aurora Borealis & Night Sky**: Tirai Aurora Borealis hijau-toska dan ungu di langit malam beserta pantulannya di air dan taburan bintang berputar.
- **Cozy Lo-Fi Rain**: Suasana hujan tenang dengan langit/kabut slate-blue sejuk, rintik hujan halus, dan pantulan lentera hangat di permukaan basah.
- **Dynamic Hand & Offhand Light**: Sorotan cahaya membulat halus per-piksel saat memegang obor di tangan kanan atau tangan kiri (offhand) dengan kedipan api tipis dan warna akurat per tipe item.
- **3D Hardware Blocky Clouds**: Awan kotak 3D bervolume bawaan Horizon yang di-cache di memori dengan biaya 0 ms di shader langit.
- **Quarter-Res Volumetric Godrays & Soft Bloom**: Sinar matahari tembus pepohonan dan pendaran cahaya pada skala 0.25x.
- **Crystal Clear Water**: Refraksi dasar air, penyerapan warna toska berdasarkan kedalaman, dan kilau pantulan matahari.
- **Glowing Ores in Darkness**: Urat mineral bijih menyala di kegelapan gua tanpa membuat batu sekitarnya ikut terang.
- **Colored Block Light**: Nuansa warna khas untuk obor, soul torch, redstone, lava, dan kristal amethyst.
