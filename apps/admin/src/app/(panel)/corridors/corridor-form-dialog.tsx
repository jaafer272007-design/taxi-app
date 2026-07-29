"use client";

import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { IRAQI_CITIES } from "@/lib/cities";
import type { Corridor } from "@/lib/types";
import {
  corridorFormSchema,
  type CorridorFormValues,
} from "./corridor-form-schema";
import { createCorridorAction, updateCorridorAction } from "./actions";

interface CorridorFormDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Present → edit mode; absent → create mode. */
  corridor?: Corridor;
}

export function CorridorFormDialog({
  open,
  onOpenChange,
  corridor,
}: CorridorFormDialogProps) {
  const isEdit = Boolean(corridor);
  const [active, setActive] = useState(corridor?.active ?? true);
  const [formError, setFormError] = useState<string | null>(null);

  const form = useForm<CorridorFormValues>({
    resolver: zodResolver(corridorFormSchema),
    defaultValues: {
      originCity: corridor?.originCity ?? "",
      destCity: corridor?.destCity ?? "",
      pricePerSeat: corridor?.pricePerSeat ?? ("" as unknown as number),
    },
  });

  // Reset the form whenever the dialog is (re-)opened for a (possibly
  // different) corridor, so stale values from a previous edit don't linger.
  useEffect(() => {
    if (open) {
      form.reset({
        originCity: corridor?.originCity ?? "",
        destCity: corridor?.destCity ?? "",
        pricePerSeat: corridor?.pricePerSeat ?? ("" as unknown as number),
      });
      setActive(corridor?.active ?? true);
      setFormError(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, corridor]);

  const originCity = form.watch("originCity");
  const destCity = form.watch("destCity");

  async function onSubmit(values: CorridorFormValues) {
    setFormError(null);
    const result = isEdit
      ? await updateCorridorAction(corridor!.id, { ...values, active })
      : await createCorridorAction(values);

    if (!result.ok) {
      setFormError(result.message);
      toast.error(result.message);
      return;
    }

    toast.success(isEdit ? "تم حفظ التغييرات" : "تم إنشاء الممر");
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isEdit ? "تعديل الممر" : "أنشئ ممراً جديداً"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "عدّل السعر أو المسار، أو بدّل حالة التفعيل."
              : "اختر مدينتي الانطلاق والوصول، ثم حدّد السعر للمقعد (IQD)."}
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="grid gap-4">
            <FormField
              control={form.control}
              name="originCity"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>من</FormLabel>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="اختر مدينة الانطلاق" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {IRAQI_CITIES.filter((c) => c.key !== destCity).map((c) => (
                        <SelectItem key={c.key} value={c.key}>
                          {c.ar}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="destCity"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>إلى</FormLabel>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="اختر مدينة الوصول" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {IRAQI_CITIES.filter((c) => c.key !== originCity).map((c) => (
                        <SelectItem key={c.key} value={c.key}>
                          {c.ar}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="pricePerSeat"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>السعر للمقعد (IQD)</FormLabel>
                  <FormControl>
                    <Input
                      type="number"
                      inputMode="numeric"
                      min={1}
                      step={1}
                      dir="ltr"
                      className="text-start"
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            {isEdit && (
              <div className="flex items-center justify-between rounded-md border border-border px-3 py-3">
                <Label htmlFor="active-toggle" className="cursor-pointer">
                  الممر نشط (قابل للحجز والنشر)
                </Label>
                <Switch id="active-toggle" checked={active} onCheckedChange={setActive} />
              </div>
            )}

            {formError && (
              <p role="alert" className="text-sm font-medium text-destructive">
                {formError}
              </p>
            )}

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => onOpenChange(false)}
                disabled={form.formState.isSubmitting}
              >
                إلغاء
              </Button>
              <Button type="submit" disabled={form.formState.isSubmitting}>
                {form.formState.isSubmitting && (
                  <Loader2 className="size-4 animate-spin" />
                )}
                {isEdit ? "حفظ" : "إنشاء"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
