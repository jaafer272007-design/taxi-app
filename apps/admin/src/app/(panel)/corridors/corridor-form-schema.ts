import { z } from "zod";

import { CITY_KEY_TUPLE } from "@/lib/cities";

export const corridorFormSchema = z
  .object({
    originCity: z.enum(CITY_KEY_TUPLE, {
      errorMap: () => ({ message: "اختر مدينة الانطلاق." }),
    }),
    destCity: z.enum(CITY_KEY_TUPLE, {
      errorMap: () => ({ message: "اختر مدينة الوصول." }),
    }),
    pricePerSeat: z.coerce
      .number({ invalid_type_error: "أدخل رقماً صحيحاً." })
      .int({ message: "السعر يجب أن يكون رقماً صحيحاً." })
      .min(1, { message: "السعر يجب أن يكون أكبر من صفر." }),
  })
  .refine((v) => v.originCity !== v.destCity, {
    message: "لا يمكن أن تكون مدينة الانطلاق والوصول متطابقتين.",
    path: ["destCity"],
  });

export type CorridorFormValues = z.infer<typeof corridorFormSchema>;
