<!DOCTYPE html>

<html class="dark" lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>ZVELT | Running Progress</title>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&amp;family=Inter:wght@300;400;500;600&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<script id="tailwind-config">
    tailwind.config = {
      darkMode: "class",
      theme: {
        extend: {
          "colors": {
            "surface": "#121316",
            "surface-bright": "#38393c",
            "error-container": "#93000a",
            "error": "#ffb4ab",
            "secondary": "#adc6ff",
            "on-surface": "#e3e2e6",
            "on-tertiary-fixed": "#001f26",
            "tertiary-container": "#35cfef",
            "on-primary-fixed": "#002019",
            "on-secondary-fixed": "#001a41",
            "surface-container-low": "#1b1b1f",
            "on-tertiary": "#003640",
            "inverse-surface": "#e3e2e6",
            "tertiary-fixed": "#acedff",
            "surface-container": "#1f1f23",
            "inverse-on-surface": "#2f3034",
            "secondary-fixed": "#d8e2ff",
            "background": "#121316",
            "on-surface-variant": "#bacac3",
            "primary-fixed": "#52fcd3",
            "surface-variant": "#343538",
            "outline-variant": "#3b4a44",
            "on-primary-fixed-variant": "#005141",
            "on-primary": "#00382c",
            "primary-container": "#00d7b0",
            "on-error-container": "#ffdad6",
            "surface-tint": "#21dfb8",
            "on-background": "#e3e2e6",
            "primary": "#46f4cb",
            "on-tertiary-container": "#005564",
            "tertiary": "#8ee7ff",
            "surface-container-lowest": "#0d0e11",
            "primary-fixed-dim": "#21dfb8",
            "secondary-container": "#0264d4",
            "surface-container-high": "#292a2d",
            "on-primary-container": "#005847",
            "outline": "#84948e",
            "secondary-fixed-dim": "#adc6ff",
            "inverse-primary": "#006b57",
            "on-error": "#690005",
            "surface-container-highest": "#343538",
            "on-secondary-container": "#e0e8ff",
            "on-secondary": "#002e69",
            "tertiary-fixed-dim": "#42d7f8",
            "surface-dim": "#121316",
            "on-secondary-fixed-variant": "#004494",
            "on-tertiary-fixed-variant": "#004e5c"
          },
          "borderRadius": {
            "DEFAULT": "0.125rem",
            "lg": "0.25rem",
            "xl": "0.5rem",
            "full": "0.75rem"
          },
          "fontFamily": {
            "headline": ["Manrope"],
            "body": ["Inter"],
            "label": ["Inter"]
          }
        },
      },
    }
  </script>
<style>
    .material-symbols-outlined {
      font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
    }
    body {
      background-color: #121316;
      color: #e3e2e6;
      font-family: 'Inter', sans-serif;
    }
    .hide-scrollbar::-webkit-scrollbar {
      display: none;
    }
    .glass-nav {
      background: rgba(18, 19, 22, 0.8);
      backdrop-filter: blur(12px);
    }
    .pace-chart-gradient {
      background: linear-gradient(180deg, rgba(70, 244, 203, 0.1) 0%, rgba(70, 244, 203, 0) 100%);
    }
  </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="antialiased selection:bg-primary-container selection:text-on-primary-container">
<!-- TopAppBar -->
<header class="fixed top-0 w-full z-50 bg-[#121316]/80 backdrop-blur-lg dark:bg-[#121316]/80">
<div class="flex justify-between items-center px-6 py-4 w-full">
<div class="flex items-center gap-3">
<div class="w-8 h-8 rounded-full bg-surface-container-high overflow-hidden">
<img class="w-full h-full object-cover" data-alt="Portrait of a determined male runner with focused expression, cinematic lighting on dark background" src="https://lh3.googleusercontent.com/aida-public/AB6AXuBTQ3Z03MZ9UYHtdG65E5DXz-7oTM0T2X7ekBziIZFgc7lYFcBYtFfaimbxTbmux6BHQtlLkVmvvpHPosS9bTO5EQMF532Xn-k1EQq5-rYBurYhRmcEyZSBWK56ATQvDH-0rgCtuELfhogELu_W-DmKibo51D1J8DNu83BEhEaKuw4LMIWSaTcTYZpBYa8ETi0U__WIJpJ--vynAZN02HSnhwEltievmRw0Lg2tKVPqeJ_jK5QY5ncLlBW0s4pUORriNKYh6IBl54U"/>
</div>
<span class="font-manrope font-extrabold tracking-tighter text-[#F5F7FA] text-2xl">ZVELT</span>
</div>
<div class="flex items-center gap-4">
<button class="hover:bg-[#1f1f23] transition-colors p-2 rounded-lg scale-95 active:duration-150 text-[#A7B0BC]">
<span class="material-symbols-outlined">settings</span>
</button>
</div>
</div>
<div class="bg-[#1b1b1f] h-[2px] w-1/3 absolute bottom-0 left-0"></div>
</header>
<main class="pt-24 pb-32 px-6 max-w-4xl mx-auto space-y-8">
<!-- Hero Stats: Asymmetric Layout -->
<section class="flex flex-col md:flex-row justify-between items-end gap-6 border-l-2 border-primary/20 pl-6">
<div class="space-y-1">
<p class="font-label text-xs uppercase tracking-widest text-on-surface-variant">Active Season: Running</p>
<h1 class="font-headline font-extrabold text-4xl text-[#F5F7FA]">Performance Analytics</h1>
</div>
<div class="flex gap-8">
<div class="text-right">
<p class="font-label text-[10px] uppercase tracking-widest text-on-surface-variant mb-1">Total Distance</p>
<div class="flex items-baseline gap-1">
<span class="font-headline font-bold text-3xl text-primary">482.4</span>
<span class="font-label text-sm text-on-surface-variant">KM</span>
</div>
</div>
<div class="text-right">
<p class="font-label text-[10px] uppercase tracking-widest text-on-surface-variant mb-1">Avg Pace</p>
<div class="flex items-baseline gap-1">
<span class="font-headline font-bold text-3xl text-[#F5F7FA]">4'12"</span>
<span class="font-label text-sm text-on-surface-variant">/KM</span>
</div>
</div>
</div>
</section>
<!-- Pace Trend Chart Module -->
<section class="bg-surface-container-low rounded-xl p-6 relative overflow-hidden">
<div class="flex justify-between items-center mb-8">
<div>
<h3 class="font-headline font-bold text-lg text-[#F5F7FA]">Pace Trend</h3>
<p class="font-label text-xs text-on-surface-variant">Velocity variance over last 10 sessions</p>
</div>
<div class="flex gap-2">
<span class="flex items-center gap-1 px-2 py-1 bg-surface-container-high rounded text-[10px] font-bold text-primary">
<span class="w-1.5 h-1.5 rounded-full bg-primary animate-pulse"></span>
            TRENDING UP
          </span>
</div>
</div>
<!-- Simulated Technical Chart -->
<div class="h-48 w-full relative flex items-end justify-between px-2">
<!-- Chart Grid Lines -->
<div class="absolute inset-0 flex flex-col justify-between py-2 opacity-10">
<div class="border-t border-on-surface w-full"></div>
<div class="border-t border-on-surface w-full"></div>
<div class="border-t border-on-surface w-full"></div>
<div class="border-t border-on-surface w-full"></div>
</div>
<!-- Chart Line Simulation using SVG -->
<svg class="absolute inset-0 w-full h-full" preserveaspectratio="none" viewbox="0 0 100 100">
<defs>
<lineargradient id="chartFill" x1="0" x2="0" y1="0" y2="1">
<stop offset="0%" stop-color="#46f4cb" stop-opacity="0.2"></stop>
<stop offset="100%" stop-color="#46f4cb" stop-opacity="0"></stop>
</lineargradient>
</defs>
<path d="M0,60 Q10,45 20,55 T40,30 T60,40 T80,20 T100,25 L100,100 L0,100 Z" fill="url(#chartFill)"></path>
<path d="M0,60 Q10,45 20,55 T40,30 T60,40 T80,20 T100,25" fill="none" stroke="#46f4cb" stroke-width="2" vector-effect="non-scaling-stroke"></path>
</svg>
<!-- Data Points Icons (Abstracted) -->
<div class="z-10 w-full flex justify-between items-end pb-1 opacity-40">
<div class="w-1 h-1 rounded-full bg-on-surface-variant"></div>
<div class="w-1 h-1 rounded-full bg-on-surface-variant"></div>
<div class="w-1 h-1 rounded-full bg-on-surface-variant"></div>
<div class="w-1 h-1 rounded-full bg-primary"></div>
<div class="w-1 h-1 rounded-full bg-on-surface-variant"></div>
<div class="w-1 h-1 rounded-full bg-on-surface-variant"></div>
<div class="w-1 h-1 rounded-full bg-primary-fixed"></div>
</div>
</div>
<div class="flex justify-between mt-4 px-2">
<span class="font-label text-[10px] text-on-surface-variant uppercase tracking-tighter">OCT 12</span>
<span class="font-label text-[10px] text-on-surface-variant uppercase tracking-tighter">OCT 28</span>
</div>
</section>
<!-- Bento Grid Secondary Modules -->
<div class="grid grid-cols-1 md:grid-cols-2 gap-6">
<!-- Estimated Race Times -->
<div class="bg-surface-container-low rounded-xl p-6 flex flex-col justify-between">
<div class="mb-6">
<div class="flex items-center gap-2 mb-1">
<span class="material-symbols-outlined text-primary text-lg">timer</span>
<h3 class="font-headline font-bold text-[#F5F7FA]">Race Predictor</h3>
</div>
<p class="font-label text-xs text-on-surface-variant">Estimated based on current VO2 Max</p>
</div>
<div class="space-y-4">
<div class="flex justify-between items-center group">
<span class="font-label text-sm text-[#A7B0BC] group-hover:text-on-surface transition-colors">5K Run</span>
<span class="font-headline font-bold text-lg text-[#F5F7FA]">19:42</span>
</div>
<div class="h-[1px] w-full bg-surface-variant/30"></div>
<div class="flex justify-between items-center group">
<span class="font-label text-sm text-[#A7B0BC] group-hover:text-on-surface transition-colors">10K Run</span>
<span class="font-headline font-bold text-lg text-[#F5F7FA]">41:15</span>
</div>
<div class="h-[1px] w-full bg-surface-variant/30"></div>
<div class="flex justify-between items-center group">
<span class="font-label text-sm text-[#A7B0BC] group-hover:text-on-surface transition-colors">Half Marathon</span>
<span class="font-headline font-bold text-lg text-[#F5F7FA]">1:32:04</span>
</div>
</div>
</div>
<!-- Shoe Mileage Tracker -->
<div class="bg-surface-container-low rounded-xl p-6 relative overflow-hidden">
<div class="flex items-center gap-2 mb-1">
<span class="material-symbols-outlined text-primary text-lg">directions_run</span>
<h3 class="font-headline font-bold text-[#F5F7FA]">Gear Lifespan</h3>
</div>
<p class="font-label text-xs text-on-surface-variant mb-6">Nike Air Zoom Pegasus 40</p>
<div class="mt-4">
<div class="flex justify-between text-xs font-label mb-2">
<span class="text-on-surface-variant">Total Usage</span>
<span class="text-[#F5F7FA] font-bold">342 / 800 KM</span>
</div>
<!-- Progress Bar -->
<div class="w-full h-3 bg-surface-container-highest rounded-full overflow-hidden">
<div class="h-full bg-gradient-to-r from-primary to-primary-container" style="width: 42%;"></div>
</div>
</div>
<div class="mt-8 flex items-center justify-between">
<div class="bg-surface-container-high px-3 py-2 rounded-lg border-l-2 border-primary">
<p class="text-[10px] font-label text-on-surface-variant uppercase tracking-widest">Health</p>
<p class="text-sm font-headline font-bold text-[#F5F7FA]">Optimal</p>
</div>
<button class="bg-surface-container-high hover:bg-surface-variant transition-colors p-2 rounded-lg group">
<span class="material-symbols-outlined text-sm text-on-surface-variant group-hover:text-primary transition-colors">add_circle</span>
</button>
</div>
</div>
</div>
<!-- Heart Rate Intensity Distribution -->
<section class="bg-surface-container-low rounded-xl p-6">
<h3 class="font-headline font-bold text-[#F5F7FA] mb-6">Intensity Distribution</h3>
<div class="flex h-12 w-full rounded-lg overflow-hidden gap-1">
<div class="h-full bg-primary/20 flex-1 relative group cursor-help">
<div class="absolute bottom-0 left-0 w-full h-1 bg-primary/40"></div>
<div class="hidden group-hover:block absolute -top-8 left-0 bg-surface-container-high px-2 py-1 rounded text-[10px] whitespace-nowrap z-20">Zone 1: 15%</div>
</div>
<div class="h-full bg-primary/40 flex-[2] relative group cursor-help">
<div class="absolute bottom-0 left-0 w-full h-1 bg-primary/60"></div>
<div class="hidden group-hover:block absolute -top-8 left-0 bg-surface-container-high px-2 py-1 rounded text-[10px] whitespace-nowrap z-20">Zone 2: 35%</div>
</div>
<div class="h-full bg-primary/60 flex-[3] relative group cursor-help">
<div class="absolute bottom-0 left-0 w-full h-1 bg-primary/80"></div>
<div class="hidden group-hover:block absolute -top-8 left-0 bg-surface-container-high px-2 py-1 rounded text-[10px] whitespace-nowrap z-20">Zone 3: 40%</div>
</div>
<div class="h-full bg-primary flex-none w-8 relative group cursor-help">
<div class="absolute bottom-0 left-0 w-full h-1 bg-white"></div>
<div class="hidden group-hover:block absolute -top-8 right-0 bg-surface-container-high px-2 py-1 rounded text-[10px] whitespace-nowrap z-20">Zone 4: 10%</div>
</div>
</div>
<div class="flex justify-between mt-4">
<div class="flex items-center gap-1">
<span class="w-2 h-2 rounded-full bg-primary/20"></span>
<span class="text-[10px] font-label text-on-surface-variant">Z1 Recovery</span>
</div>
<div class="flex items-center gap-1">
<span class="w-2 h-2 rounded-full bg-primary/60"></span>
<span class="text-[10px] font-label text-on-surface-variant">Z3 Threshold</span>
</div>
<div class="flex items-center gap-1">
<span class="w-2 h-2 rounded-full bg-primary"></span>
<span class="text-[10px] font-label text-on-surface-variant">Z4 Anaerobic</span>
</div>
</div>
</section>
</main>
<!-- BottomNavBar -->
<nav class="fixed bottom-0 left-0 w-full z-50 bg-[#1b1b1f]/90 backdrop-blur-2xl dark:bg-[#1b1b1f]/90 rounded-t-xl shadow-[0px_12px_32px_rgba(0,0,0,0.4)]">
<div class="flex justify-around items-center px-4 pb-6 pt-3">
<a class="flex flex-col items-center justify-center text-[#A7B0BC] opacity-60 hover:text-[#F5F7FA] transition-all duration-300 ease-out" href="#">
<span class="material-symbols-outlined">home</span>
<span class="font-manrope text-[10px] uppercase tracking-widest font-medium">Home</span>
</a>
<a class="flex flex-col items-center justify-center text-[#A7B0BC] opacity-60 hover:text-[#F5F7FA] transition-all duration-300 ease-out" href="#">
<span class="material-symbols-outlined">exercise</span>
<span class="font-manrope text-[10px] uppercase tracking-widest font-medium">Workout</span>
</a>
<!-- Active: Progress -->
<a class="flex flex-col items-center justify-center text-[#46f4cb] bg-[#292a2d] rounded-lg px-3 py-1 transition-all duration-300 ease-out" href="#">
<span class="material-symbols-outlined" style="font-variation-settings: 'FILL' 1;">monitoring</span>
<span class="font-manrope text-[10px] uppercase tracking-widest font-medium">Progress</span>
</a>
<a class="flex flex-col items-center justify-center text-[#A7B0BC] opacity-60 hover:text-[#F5F7FA] transition-all duration-300 ease-out" href="#">
<span class="material-symbols-outlined">group</span>
<span class="font-manrope text-[10px] uppercase tracking-widest font-medium">Social</span>
</a>
<a class="flex flex-col items-center justify-center text-[#A7B0BC] opacity-60 hover:text-[#F5F7FA] transition-all duration-300 ease-out" href="#">
<span class="material-symbols-outlined">person</span>
<span class="font-manrope text-[10px] uppercase tracking-widest font-medium">Profile</span>
</a>
</div>
</nav>
</body></html>