type CamelCase<S extends string> = S extends `${infer Head}_${infer Tail}`
  ? `${Head}${Capitalize<CamelCase<Tail>>}`
  : S

type CamelCaseKeys<T> = {
  [K in keyof T as K extends string ? CamelCase<K> : K]: T[K]
}

export type SnakeMailer = {
  mailer_name: string
  action_name: string
}

export type SnakeMessage = {
  subject: string | null
  to: string[] | null
  cc: string[] | null
  bcc: string[] | null
  from: string[] | null
  reply_to: string[] | null
}

export type CamelMailer = CamelCaseKeys<SnakeMailer>
export type CamelMessage = CamelCaseKeys<SnakeMessage>
