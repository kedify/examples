/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  swcMinify: true,
};

module.exports = nextConfig;

// fail fast if any required env vars are not initialized
const requiredEnvVars = [
  'AMQP_URL',
];

if (!['lint', 'lint-fix', 'build', 'format', 'test', 'test:watch'].includes(process.env.npm_lifecycle_event)) {
  requiredEnvVars.forEach((envVar) => {
    if (process.env[envVar] === undefined) {
      throw new Error(`Environment variable ${envVar} is not initialized!`);
    }
  });
}
