const { defineConfig } = require('@vue/cli-service')

module.exports = defineConfig({
  transpileDependencies: true,
  devServer: {
    allowedHosts: 'all'
  },
  publicPath: process.env.NODE_ENV === 'production'
    ? '/momo-store/'
    : '/'
})
