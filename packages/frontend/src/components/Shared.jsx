export const Button = ({ children, variant = 'primary', onClick, disabled, className = '', ...props }) => {
  const baseClasses = 'px-6 py-3 rounded-xl font-semibold transition-all duration-300 focus:outline-none focus:ring-4';
  const variants = {
    primary: 'bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-200 disabled:bg-gray-400',
    secondary: 'bg-white text-blue-600 border-2 border-blue-600 hover:bg-blue-600 hover:text-white focus:ring-blue-200',
    danger: 'bg-red-600 text-white hover:bg-red-700 focus:ring-red-200',
    ghost: 'bg-transparent text-blue-600 hover:bg-blue-50 focus:ring-blue-200'
  };

  return (
    <button
      className={`${baseClasses} ${variants[variant]} ${className} ${disabled ? 'cursor-not-allowed' : 'cursor-pointer'}`}
      onClick={onClick}
      disabled={disabled}
      {...props}
    >
      {children}
    </button>
  );
};

export const Card = ({ children, className = '', hover = false }) => {
  const hoverClasses = hover ? 'hover:shadow-lg hover:-translate-y-1' : '';
  return (
    <div className={`bg-white rounded-2xl shadow-md p-6 transition-all duration-300 ${hoverClasses} ${className}`}>
      {children}
    </div>
  );
};

export const Input = ({ label, error, className = '', ...props }) => {
  return (
    <div className="space-y-2">
      {label && <label className="block text-sm font-semibold text-gray-700">{label}</label>}
      <input
        className={`w-full px-4 py-3 border-2 rounded-xl focus:outline-none focus:border-blue-600 transition-colors ${
          error ? 'border-red-500' : 'border-gray-200'
        } ${className}`}
        {...props}
      />
      {error && <p className="text-red-500 text-sm">{error}</p>}
    </div>
  );
};

export const Select = ({ label, options, error, className = '', ...props }) => {
  return (
    <div className="space-y-2">
      {label && <label className="block text-sm font-semibold text-gray-700">{label}</label>}
      <select
        className={`w-full px-4 py-3 border-2 rounded-xl focus:outline-none focus:border-blue-600 transition-colors cursor-pointer ${
          error ? 'border-red-500' : 'border-gray-200'
        } ${className}`}
        {...props}
      >
        {options.map((option, index) => (
          <option key={index} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      {error && <p className="text-red-500 text-sm">{error}</p>}
    </div>
  );
};