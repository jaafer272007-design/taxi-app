-- CreateEnum
CREATE TYPE "Gender" AS ENUM ('MALE', 'FEMALE');

-- CreateEnum
CREATE TYPE "TripType" AS ENUM ('GENERAL', 'WOMEN_FAMILY');

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "gender" "Gender";

-- AlterTable
ALTER TABLE "Trip" ADD COLUMN     "tripType" "TripType" NOT NULL DEFAULT 'GENERAL';
