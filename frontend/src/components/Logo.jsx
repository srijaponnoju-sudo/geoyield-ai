export default function Logo({ size = 32 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 40 40" aria-hidden="true">
      <rect width="40" height="40" rx="11" fill="#0b1f3a" />
      <path d="M12 28c0-9 6-15 16-16 0 10-6 16-16 16z" fill="#22c55e" />
      <path d="M12 28c4-5 8-8 13-11" stroke="#0b1f3a" strokeWidth="1.8" fill="none" strokeLinecap="round" />
    </svg>
  );
}
