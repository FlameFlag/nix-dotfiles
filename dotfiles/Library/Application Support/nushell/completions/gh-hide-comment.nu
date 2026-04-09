# Completions for gh-hide-comment.
# Reasons mirror the GitHub GraphQL `ReportedContentClassifiers` enum:
#   gh api graphql -f query='{ __type(name: "ReportedContentClassifiers") { enumValues { name } } }'
def "nu-complete gh-hide-comment reasons" []: nothing -> list<record<value: string, description: string>> {
    [
        { value: "OUTDATED",  description: "An outdated piece of content" }
        { value: "DUPLICATE", description: "A duplicated piece of content" }
        { value: "OFF_TOPIC", description: "An irrelevant piece of content" }
        { value: "RESOLVED",  description: "The content has been resolved" }
        { value: "SPAM",      description: "A spammy piece of content" }
        { value: "ABUSE",     description: "An abusive or harassing piece of content" }
    ]
}

# Hide GitHub comments by minimizing them via the GraphQL minimizeComment mutation.
export extern "gh-hide-comment" [
    --reason: string@"nu-complete gh-hide-comment reasons"  # Classifier for why the comment is being hidden
    ...urls: string                                          # Comment URLs (omit for interactive mode)
]
