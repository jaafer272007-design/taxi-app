import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  // Non-negotiable constant: the whole app runs on Baghdad time.
  process.env.TZ = process.env.TZ || 'Asia/Baghdad';

  const app = await NestFactory.create(AppModule);

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.enableCors();

  const port = Number(process.env.PORT) || 3000;
  await app.listen(port);
  Logger.log(`Taxi API listening on :${port} (TZ=${process.env.TZ})`, 'Bootstrap');
}

bootstrap();
