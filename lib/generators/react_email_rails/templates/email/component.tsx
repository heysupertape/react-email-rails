import { Body, Container, Heading, Html, Text } from "@react-email/components"

export default function <%= @component_name %>() {
  return (
    <Html>
      <Body>
        <Container>
          <Heading><%= class_name %>Mailer#<%= @action %></Heading>
          <Text>Hi, find me in <%= @path %></Text>
        </Container>
      </Body>
    </Html>
  )
}
