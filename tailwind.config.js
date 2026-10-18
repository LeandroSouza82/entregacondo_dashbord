/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        navy: {
          950: '#080E17',
          900: '#0B1320',
          850: '#0D1726',
          800: '#0F1B2D', // Cor primária do Menu Lateral
          750: '#132137',
          700: '#1A2D4A',
          600: '#243C62',
          500: '#325285',
          100: '#E3E9F3',
          50: '#F0F4FA',
        },
        terracotta: {
          50: '#FFF7ED',
          100: '#FFEDD5',
          200: '#FED7AA',
          300: '#FDBA74',
          400: '#FB923C',
          500: '#F97316',
          600: '#C2410C', // Destaque Laranja-terracota solicitado
          700: '#9A3412',
          800: '#7C2D12',
          900: '#431407',
        },
        surface: {
          DEFAULT: '#F3F5F8', // Fundo principal da área de conteúdo
          card: '#FFFFFF',
          border: '#E2E8F0',
          muted: '#64748B',
        }
      },
      fontFamily: {
        sans: ['"Plus Jakarta Sans"', 'system-ui', '-apple-system', 'sans-serif'],
      },
      boxShadow: {
        'subtle': '0 1px 3px 0 rgba(15, 27, 45, 0.05), 0 1px 2px 0 rgba(15, 27, 45, 0.03)',
        'card': '0 4px 6px -1px rgba(15, 27, 45, 0.05), 0 2px 4px -2px rgba(15, 27, 45, 0.03)',
        'floating': '0 10px 25px -5px rgba(15, 27, 45, 0.1), 0 8px 10px -6px rgba(15, 27, 45, 0.05)',
      }
    },
  },
  plugins: [],
}
