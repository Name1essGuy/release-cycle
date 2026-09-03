const { defineConfig } = require('@vue/cli-service')

module.exports = defineConfig({
  transpileDependencies: true,
  devServer: {
    allowedHosts: 'all',
    proxy: {
      '/api': {
        target: 'http://backend:8081',
        changeOrigin: true,
        pathRewrite: { '^/api': '' }
      }
    }
  },
  publicPath: process.env.NODE_ENV === 'production'
    ? '/momo-store/'
    : '/'
})