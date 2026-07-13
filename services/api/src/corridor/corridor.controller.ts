import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CorridorService } from './corridor.service';
import { CreateCorridorDto } from './dto/create-corridor.dto';
import { UpdateCorridorDto } from './dto/update-corridor.dto';

@Controller('corridors')
export class CorridorController {
  constructor(private readonly corridor: CorridorService) {}

  // Any authenticated user can browse corridors (drivers need them to post trips).
  @Get()
  @UseGuards(JwtAuthGuard)
  list() {
    return this.corridor.list();
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  create(@Body() dto: CreateCorridorDto) {
    return this.corridor.create(dto);
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  update(@Param('id') id: string, @Body() dto: UpdateCorridorDto) {
    return this.corridor.update(id, dto);
  }
}
