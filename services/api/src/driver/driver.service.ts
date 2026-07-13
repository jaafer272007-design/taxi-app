import {
  Injectable,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import {
  DocStatus,
  DocType,
  DriverProfile,
  DriverStatus,
  UserRole,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { CreateVehicleDto } from './dto/create-vehicle.dto';

const ALLOWED_DOC_MIME = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

@Injectable()
export class DriverService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  /** Become a driver: create a PENDING DriverProfile and grant the DRIVER role. */
  async createProfile(userId: string): Promise<DriverProfile> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('المستخدم غير موجود.');
    }

    const existing = await this.prisma.driverProfile.findUnique({ where: { userId } });
    if (existing) {
      throw new ConflictException('أنت مسجّل سائق بالفعل.');
    }

    const roles = Array.from(new Set([...user.roles, UserRole.DRIVER]));

    return this.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: userId }, data: { roles: { set: roles } } });
      return tx.driverProfile.create({
        data: { userId, status: DriverStatus.PENDING },
      });
    });
  }

  /** Add or replace the driver's vehicle (one vehicle per driver). */
  async upsertVehicle(userId: string, dto: CreateVehicleDto) {
    const profile = await this.getProfileOrThrow(userId);
    return this.prisma.vehicle.upsert({
      where: { driverId: profile.id },
      update: { ...dto },
      create: { driverId: profile.id, ...dto },
    });
  }

  /** Upload one identity/vehicle document; stored locally in dev, status PENDING. */
  async uploadDocument(userId: string, type: DocType, file?: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('الملف مطلوب.');
    }
    if (!ALLOWED_DOC_MIME.includes(file.mimetype)) {
      throw new BadRequestException('نوع الملف غير مدعوم (صورة أو PDF فقط).');
    }

    const profile = await this.getProfileOrThrow(userId);
    const url = await this.storage.save(file.buffer, file.originalname, `drivers/${profile.id}`);

    const doc = await this.prisma.document.create({
      data: { driverId: profile.id, type, url, status: DocStatus.PENDING },
    });

    return { id: doc.id, type: doc.type, status: doc.status, url: doc.url };
  }

  /** The current driver's profile with vehicle, documents, and approval status. */
  async getProfile(userId: string) {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
      include: { vehicle: true, documents: true },
    });
    if (!profile) {
      throw new NotFoundException('لا يوجد ملف سائق. سجّل كسائق أولاً (POST /driver/profile).');
    }
    return profile;
  }

  /**
   * Gate reused by the trip module in Step 3: only an APPROVED driver may post
   * trips. Enforced here now so the rule lives in one place.
   */
  async assertApprovedDriver(userId: string): Promise<DriverProfile> {
    const profile = await this.getProfileOrThrow(userId);
    if (profile.status !== DriverStatus.APPROVED) {
      throw new ForbiddenException('يجب اعتماد حسابك كسائق قبل إعلان الرحلات.');
    }
    return profile;
  }

  /** Non-throwing lookup used by the trip module (e.g. listing a user's trips). */
  findProfileByUserId(userId: string): Promise<DriverProfile | null> {
    return this.prisma.driverProfile.findUnique({ where: { userId } });
  }

  private async getProfileOrThrow(userId: string): Promise<DriverProfile> {
    const profile = await this.prisma.driverProfile.findUnique({ where: { userId } });
    if (!profile) {
      throw new BadRequestException('يجب أن تسجّل كسائق أولاً (POST /driver/profile).');
    }
    return profile;
  }
}
