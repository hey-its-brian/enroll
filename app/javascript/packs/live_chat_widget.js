CXBus.configure({
  debug: false,
  pluginsPath: 'https://apps.usw2.pure.cloud/widgets/9.0/plugins/',
});
CXBus.loadPlugin('widgets-core');

$(document).on('turbolinks:load', function () {
  $(document).on('click', '.qna-bot-open-click-button', function () {
    openQnaBot();
  });

  $(document).on('click', '.live-webchat-open-click-button', function () {
    customPlugin.command('WebChat.open', getAdvancedConfig());
  });
});
