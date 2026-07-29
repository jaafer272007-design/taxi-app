export interface Corridor {
  id: string;
  originCity: string;
  destCity: string;
  active: boolean;
  pricePerSeat: number;
}

export interface AuthUser {
  id: string;
  phone: string;
  name: string | null;
  roles: string[];
}

export interface AuthSession {
  accessToken: string;
  user: AuthUser;
}
