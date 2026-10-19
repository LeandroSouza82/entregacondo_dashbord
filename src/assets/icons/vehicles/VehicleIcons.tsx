import React from 'react';

export type TipoVeiculoIcone = 'moto' | 'carro' | 'caminhao';

export interface VehicleIconProps extends React.SVGProps<SVGSVGElement> {
  size?: number;
  className?: string;
  primaryColor?: string;
  accentColor?: string;
}

/**
 * Ícone SVG de Moto de Entrega (com baú característico de entrega expressa)
 */
export const IconeMoto: React.FC<VehicleIconProps> = ({
  size = 28,
  className = '',
  primaryColor = '#0F172A',
  accentColor = '#D94E1F',
  ...props
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 32 32"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
    {...props}
  >
    {/* Roda Traseira */}
    <circle cx="7" cy="22" r="4.5" stroke={primaryColor} strokeWidth="2.2" fill="#334155" />
    <circle cx="7" cy="22" r="1.8" fill="#F8FAFC" />

    {/* Roda Dianteira */}
    <circle cx="25" cy="22" r="4.5" stroke={primaryColor} strokeWidth="2.2" fill="#334155" />
    <circle cx="25" cy="22" r="1.8" fill="#F8FAFC" />

    {/* Quadro / Chassi da Moto */}
    <path
      d="M7 22L12 16H18L21 11H24"
      stroke={primaryColor}
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M18 16L25 22"
      stroke={primaryColor}
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M12 16L14 22H19"
      stroke={primaryColor}
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    />

    {/* Guidão e Farol */}
    <path
      d="M20 9L23 11L25 10.5"
      stroke={accentColor}
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <circle cx="25.5" cy="11.5" r="1" fill="#FBBF24" />

    {/* Tanque de Combustível */}
    <path
      d="M15 14.5C15 13.5 16.5 12.5 18.5 13C19.5 13.3 20 14.2 19.5 15L15 15.2"
      fill={accentColor}
    />

    {/* Baú de Entregas EntregaCondo */}
    <rect
      x="5"
      y="9.5"
      width="8"
      height="7.5"
      rx="1.5"
      fill={accentColor}
      stroke={primaryColor}
      strokeWidth="1.6"
    />
    {/* Faixa reflexiva do baú */}
    <rect x="5.5" y="12.5" width="7" height="1.5" fill="#FFFFFF" fillOpacity="0.8" rx="0.5" />
  </svg>
);

/**
 * Ícone SVG de Carro / Veículo Leve / Fiorino de Entrega
 */
export const IconeCarro: React.FC<VehicleIconProps> = ({
  size = 28,
  className = '',
  primaryColor = '#0F172A',
  accentColor = '#D94E1F',
  ...props
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 32 32"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
    {...props}
  >
    {/* Roda Traseira */}
    <circle cx="9" cy="22.5" r="3.5" stroke={primaryColor} strokeWidth="2.2" fill="#334155" />
    <circle cx="9" cy="22.5" r="1.5" fill="#F8FAFC" />

    {/* Roda Dianteira */}
    <circle cx="23" cy="22.5" r="3.5" stroke={primaryColor} strokeWidth="2.2" fill="#334155" />
    <circle cx="23" cy="22.5" r="1.5" fill="#F8FAFC" />

    {/* Carroceria / Baú Furgão */}
    <path
      d="M4 17V11C4 9.89543 4.89543 9 6 9H17V17H4Z"
      fill={accentColor}
      stroke={primaryColor}
      strokeWidth="1.8"
      strokeLinejoin="round"
    />

    {/* Cabine Dianteira */}
    <path
      d="M17 9H21C21.8 9 22.5 9.5 23 10.5L26 15V20C26 20.6 25.5 21 25 21H23M17 21H9M4 20V17H17V21H9"
      stroke={primaryColor}
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      fill="#F1F5F9"
    />

    {/* Para-brisa */}
    <path
      d="M18 10.5H20.8L23.5 15H18V10.5Z"
      fill="#38BDF8"
      fillOpacity="0.85"
      stroke={primaryColor}
      strokeWidth="1.4"
      strokeLinejoin="round"
    />

    {/* Farol Dianteiro */}
    <rect x="25" y="16" width="1.8" height="2" rx="0.5" fill="#FBBF24" />

    {/* Faixa Lateral com Logo Marca */}
    <rect x="6" y="12" width="9" height="1.8" rx="0.5" fill="#FFFFFF" fillOpacity="0.85" />
  </svg>
);

/**
 * Ícone SVG de Caminhão / Utilitário Pesado de Entrega
 */
export const IconeCaminhao: React.FC<VehicleIconProps> = ({
  size = 28,
  className = '',
  primaryColor = '#0F172A',
  accentColor = '#D94E1F',
  ...props
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 32 32"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
    {...props}
  >
    {/* Rodas Traseiras Duplas */}
    <circle cx="8" cy="23" r="3.2" stroke={primaryColor} strokeWidth="2" fill="#334155" />
    <circle cx="8" cy="23" r="1.3" fill="#F8FAFC" />
    <circle cx="14" cy="23" r="3.2" stroke={primaryColor} strokeWidth="2" fill="#334155" />
    <circle cx="14" cy="23" r="1.3" fill="#F8FAFC" />

    {/* Roda Dianteira */}
    <circle cx="24.5" cy="23" r="3.2" stroke={primaryColor} strokeWidth="2" fill="#334155" />
    <circle cx="24.5" cy="23" r="1.3" fill="#F8FAFC" />

    {/* Baú de Carga Grande */}
    <rect
      x="3"
      y="7"
      width="15"
      height="13.5"
      rx="1.5"
      fill={accentColor}
      stroke={primaryColor}
      strokeWidth="1.8"
    />
    {/* Detalhes do Baú / Portas Traseiras */}
    <line x1="6" y1="7.5" x2="6" y2="20" stroke="#FFFFFF" strokeOpacity="0.4" strokeWidth="1" />
    <line x1="12" y1="7.5" x2="12" y2="20" stroke="#FFFFFF" strokeOpacity="0.4" strokeWidth="1" />
    <rect x="4.5" y="12" width="12" height="2" fill="#FFFFFF" fillOpacity="0.85" rx="0.5" />

    {/* Cabine do Caminhão */}
    <path
      d="M18 10H23.5C24.5 10 25.2 10.6 25.6 11.5L27.5 16V21C27.5 21.6 27 22 26.5 22H24.5M18 22H14M18 20.5V10Z"
      fill="#F8FAFC"
      stroke={primaryColor}
      strokeWidth="1.8"
      strokeLinejoin="round"
    />

    {/* Janela da Cabine */}
    <path
      d="M19.5 11.5H23L24.8 15.5H19.5V11.5Z"
      fill="#38BDF8"
      fillOpacity="0.85"
      stroke={primaryColor}
      strokeWidth="1.4"
      strokeLinejoin="round"
    />

    {/* Farol */}
    <rect x="26.5" y="17.5" width="1.8" height="2.2" rx="0.6" fill="#FBBF24" />
  </svg>
);

/**
 * Retorna o ícone SVG apropriado conforme o tipo de veículo do motorista
 */
export const ObterIconeVeiculo: React.FC<{
  tipo: TipoVeiculoIcone | string;
  size?: number;
  className?: string;
  primaryColor?: string;
  accentColor?: string;
}> = ({ tipo, size = 24, className, primaryColor, accentColor }) => {
  const norm = String(tipo || 'moto').toLowerCase();

  if (norm.includes('caminh') || norm.includes('truck') || norm.includes('pesado')) {
    return <IconeCaminhao size={size} className={className} primaryColor={primaryColor} accentColor={accentColor} />;
  }
  if (norm.includes('carro') || norm.includes('fiorino') || norm.includes('van') || norm.includes('strada') || norm.includes('auto')) {
    return <IconeCarro size={size} className={className} primaryColor={primaryColor} accentColor={accentColor} />;
  }
  return <IconeMoto size={size} className={className} primaryColor={primaryColor} accentColor={accentColor} />;
};
