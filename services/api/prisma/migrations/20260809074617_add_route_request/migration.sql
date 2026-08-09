-- AlterEnum
ALTER TYPE "NotificationType" ADD VALUE 'ROUTE_AVAILABLE';

-- CreateTable
CREATE TABLE "RouteRequest" (
    "id" TEXT NOT NULL,
    "riderId" TEXT NOT NULL,
    "corridorId" TEXT NOT NULL,
    "requestedFor" TIMESTAMP(3),
    "requestedDay" DATE NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fulfilledAt" TIMESTAMP(3),
    "fulfilledByTripId" TEXT,

    CONSTRAINT "RouteRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "RouteRequest_corridorId_fulfilledAt_createdAt_idx" ON "RouteRequest"("corridorId", "fulfilledAt", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "RouteRequest_riderId_corridorId_requestedDay_key" ON "RouteRequest"("riderId", "corridorId", "requestedDay");

-- AddForeignKey
ALTER TABLE "RouteRequest" ADD CONSTRAINT "RouteRequest_corridorId_fkey" FOREIGN KEY ("corridorId") REFERENCES "Corridor"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
