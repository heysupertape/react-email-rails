import type { CamelMailer, CamelMessage, Mailer, Message } from "react-email-rails"
import type { Mailer as RuntimeMailer, Message as RuntimeMessage } from "react-email-rails/runtime"

export function defaultMailer(mailer: Mailer) {
  const mailerName: string = mailer.mailer_name
  const actionName: string = mailer.action_name
  return { mailerName, actionName }
}

export function defaultMailerIsNotCamel(mailer: Mailer) {
  // @ts-expect-error
  return mailer.mailerName
}

export function defaultMessage(message: Message) {
  const subject: string | null = message.subject
  const to: string[] | null = message.to
  const cc: string[] | null = message.cc
  const bcc: string[] | null = message.bcc
  const from: string[] | null = message.from
  const replyTo: string[] | null = message.reply_to
  return { subject, to, cc, bcc, from, replyTo }
}

export function defaultMessageIsNotCamel(message: Message) {
  // @ts-expect-error
  return message.replyTo
}

export function camelMailer(mailer: CamelMailer) {
  const mailerName: string = mailer.mailerName
  const actionName: string = mailer.actionName
  return { mailerName, actionName }
}

export function camelMailerIsNotSnake(mailer: CamelMailer) {
  // @ts-expect-error
  return mailer.mailer_name
}

export function camelMessage(message: CamelMessage) {
  const subject: string | null = message.subject
  const to: string[] | null = message.to
  const cc: string[] | null = message.cc
  const bcc: string[] | null = message.bcc
  const from: string[] | null = message.from
  const replyTo: string[] | null = message.replyTo
  return { subject, to, cc, bcc, from, replyTo }
}

export function camelMessageIsNotSnake(message: CamelMessage) {
  // @ts-expect-error
  return message.reply_to
}

export function runtimeMailer(mailer: RuntimeMailer) {
  const mailerName: string = mailer.mailer_name
  const actionName: string = mailer.action_name
  return { mailerName, actionName }
}

export function runtimeMessage(message: RuntimeMessage) {
  const replyTo: string[] | null = message.reply_to
  return replyTo
}
