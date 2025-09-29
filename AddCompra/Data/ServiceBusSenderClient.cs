using Azure.Messaging.ServiceBus;
using System.Text;
using System.Text.Json;

namespace AddCompra.Data;

public class ServiceBusSenderClient : IAsyncDisposable
{
    private readonly ServiceBusClient _client;
    private readonly string _queueName;

    public ServiceBusSenderClient(string connectionString, string queueName)
    {
        _client = new ServiceBusClient(connectionString);
        _queueName = queueName;
    }

    public async Task SendAsync<T>(T payload)
    {
        var sender = _client.CreateSender(_queueName);
        var body = JsonSerializer.Serialize(payload);
        var msg = new ServiceBusMessage(Encoding.UTF8.GetBytes(body))
        {
            ContentType = "application/json"
        };
        await sender.SendMessageAsync(msg);
    }

    public async ValueTask DisposeAsync()
    {
        await _client.DisposeAsync();
    }
}
