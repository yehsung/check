// 자리표시 화면 하나(셸 몫). 화면 갈래(W3·W4·W5)가 자기 화면을 낼 때까지 목적지마다 이것을 그린다.
// 판정을 품지 않는다(E§3 끝: Composable 은 그리기만). 이름·인자·라우트 글자를 보여 줘 기기 시험(uiautomator)과 사람이 지금 화면을 안다.
package com.yehsung.aingcheck.android.shell

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/** 자리표시 화면에서 다른 목적지로 가는 단추 하나. */
data class PlaceholderLink(val label: String, val onClick: () -> Unit)

@Composable
fun PlaceholderScreen(
    title: String,
    owner: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    links: List<PlaceholderLink> = emptyList(),
) {
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp).testTag("placeholder:$title"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, style = MaterialTheme.typography.headlineSmall)
        Text("자리표시 · $owner", style = MaterialTheme.typography.bodySmall)
        if (detail != null) Text(detail, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("placeholder-detail"))
        links.forEach { link ->
            OutlinedButton(onClick = link.onClick) { Text(link.label) }
        }
    }
}
