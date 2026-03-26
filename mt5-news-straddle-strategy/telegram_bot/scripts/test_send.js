require('dotenv').config({ path: '/opt/newsbot/.env' });
const TelegramBot = require('node-telegram-bot-api');
const config = require('../app/config');

const bot = new TelegramBot(config.TELEGRAM_BOT_TOKEN);

async function main() {
  // Get bot info to verify token works
  try {
    const me = await bot.getMe();
    console.log('Bot info:');
    console.log(`  Username: @${me.username}`);
    console.log(`  Name: ${me.first_name}`);
    console.log(`  ID: ${me.id}`);
    console.log('\nToken is valid! Bot is ready.');
    console.log('\nNext step: Open Telegram, search for @' + me.username + ', and send /start');
  } catch (err) {
    console.error('Token verification failed:', err.message);
  }
}

main();
